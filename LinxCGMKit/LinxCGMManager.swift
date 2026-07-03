import Foundation
import HealthKit
import LoopKit
import os.log
#if canImport(UIKit)
import UIKit
#endif

public protocol LinxStateObserver: AnyObject {
    func linxStateDidUpdate(_ state: LinxCGMManagerState)
    func linxStatusDidUpdate(_ status: String)
    /// A hatótávon belül érzékelt Linx szenzorok listája változott (kiválasztóhoz).
    func linxNearbyDevicesDidUpdate(_ devices: [LinxNearbyDevice])
}

public extension LinxStateObserver {
    // Visszafelé kompatibilis alapértelmezés: aki nem érdeklődik, nem kötelező.
    func linxNearbyDevicesDidUpdate(_: [LinxNearbyDevice]) {}
}

/// Egy hatótávon belül érzékelt Linx szenzor a kiválasztó listához.
public struct LinxNearbyDevice: Identifiable, Equatable {
    /// A hirdetett teljes név (pl. "LinX-2222296PN2") — ez egyben az azonosító is.
    public let name: String
    /// Utolsó mért jelerősség (dBm).
    public let rssi: Int
    public var id: String { name }
    public init(name: String, rssi: Int) {
        self.name = name
        self.rssi = rssi
    }
}

public class LinxCGMManager: CGMManager {
    private let log = OSLog(subsystem: "com.linxcgmkit", category: "LinxCGMManager")

    // MARK: - State

    private var lockedState: LinxCGMManagerState
    private let stateLock = NSLock()

    public var state: LinxCGMManagerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lockedState
    }

    private func mutateState(_ changes: (inout LinxCGMManagerState) -> Void) {
        stateLock.lock()
        var newValue = lockedState
        changes(&newValue)
        let changed = newValue != lockedState
        lockedState = newValue
        stateLock.unlock()

        if changed {
            delegateQueue?.async {
                self.cgmManagerDelegate?.cgmManagerDidUpdateState(self)
                self.cgmManagerDelegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
            }
            stateObservers.forEach { $0.linxStateDidUpdate(newValue) }
        }
    }

    private var stateObservers: [LinxStateObserver] = []

    public func addStateObserver(_ observer: LinxStateObserver) {
        stateObservers.append(observer)
    }

    public func removeStateObserver(_ observer: LinxStateObserver) {
        stateObservers.removeAll { $0 === observer }
    }

    // MARK: - Scanner

    private let scanner = LinxScanner()
    private var lastStatus: String = "Starting..."
    public var latestReading: LinxGlucoseReading?

    /// Hatótávon belül érzékelt Linx szenzorok (név → utolsó jelerősség + idő).
    /// A scanner töltögeti; a kiválasztó UI ezt listázza ki.
    private var nearbyDevicesByName: [String: (rssi: Int, seen: Date)] = [:]

    /// A jelenleg ismert, hatótávon belüli Linx szenzorok, jelerősség szerint
    /// csökkenő sorrendben. Az utóbbi 30 mp-en belül látottakat tartjuk meg.
    public var nearbyDevices: [LinxNearbyDevice] {
        let cutoff = Date().addingTimeInterval(-30)
        return nearbyDevicesByName
            .filter { $0.value.seen >= cutoff }
            .map { LinxNearbyDevice(name: $0.key, rssi: $0.value.rssi) }
            .sorted { $0.rssi > $1.rssi }
    }

    /// A Loopnak max. ennyente adunk át új mintát → CÉL: a Loop ~3 percenként
    /// aktiválódik (3 perces loop). A szkenner közben folyamatosan figyel (egy csomagot se
    /// mulasszon el háttérben), de a köztes (percenkénti) csomagokat eldobjuk, mert a Loop
    /// 3 perces rácsra dolgozik. A 10 mp tolerancia (lentebb) elnyeli a fáziscsúszást, és a
    /// downstream kapuk (GlucoseStorage filter, APSManager.canStartNewLoop) is a 3 perc ALÁ
    /// vannak állítva, hogy minden ~3 perces minta megbízhatóan loopot indítson.
    public static let loopCycleInterval: TimeInterval = 3 * 60 // 3 perc másodpercben

    /// Az utolsó, ténylegesen a Loopnak átadott minta ideje.
    private var lastSampleSentAt: Date?

    /// Az utolsó, ténylegesen a Loopnak átadott minta értéke (mg/dL).
    /// A trendet ebből + a mostani értékből SAJÁT MAGUNK számoljuk
    /// (mg/dL per perc), mert a szenzor csomag nem ad megbízható trend-irányt.
    private var lastSampleValue: Int?

    // MARK: - CGMManager protokoll

    public weak var cgmManagerDelegate: CGMManagerDelegate? {
        get { delegate.delegate }
        set { delegate.delegate = newValue }
    }

    public var delegateQueue: DispatchQueue! {
        get { delegate.queue }
        set { delegate.queue = newValue }
    }

    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    /// Mi szkennelünk BLE-n → mi szolgáltatjuk a "heartbeat"-et a Loopnak.
    public var providesBLEHeartbeat: Bool = true

    public var managedDataInterval: TimeInterval? { 3 * 60 * 60 } // 3 óra másodpercben

    public var shouldSyncToRemoteService: Bool { state.uploadReadings }

    public var glucoseDisplay: GlucoseDisplayable? { latestDisplay }

    public var cgmManagerStatus: CGMManagerStatus {
        CGMManagerStatus(hasValidSensorSession: true, device: device)
    }

    public var device: HKDevice? {
        HKDevice(
            name: state.sensorSerial ?? "Linx",
            manufacturer: "Linx",
            model: "Linx CGM",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: "LinxCGMKit",
            localIdentifier: state.sensorSerial,
            udiDeviceIdentifier: nil
        )
    }

    public static let pluginIdentifier: String = "LinxCGMManager"

    public let localizedTitle = "Linx CGM"

    public let isOnboarded = true

    public var appURL: URL? { nil }

    public var debugDescription: String {
        """
        ## LinxCGMManager
        sensorSerial: \(String(describing: state.sensorSerial))
        calA: \(state.calibration.calA) calB: \(state.calibration.calB)
        calPoints: \(state.calibration.points.count)
        latestReadingDate: \(String(describing: state.latestReadingDate))
        lastStatus: \(lastStatus)
        """
    }

    // MARK: - Init

    public init() {
        lockedState = LinxCGMManagerState()
        scanner.delegate = self
    }

    public required init?(rawState: RawStateValue) {
        lockedState = LinxCGMManagerState(rawValue: rawState)
        scanner.delegate = self
    }

    public var rawState: RawStateValue { state.rawValue }

    // MARK: - Kalibráció vezérlés (a UI hívja)

    public func addCalibration(glu10: Int, mmol: Double) {
        mutateState { state in
            state.calibration.addPoint(glu10: glu10, mmol: mmol)
        }
    }

    public func resetCalibration() {
        mutateState { state in
            state.calibration.reset()
        }
    }

    public func setSensorSerial(_ serial: String?) {
        mutateState { state in
            state.sensorSerial = (serial?.isEmpty == true) ? nil : serial
        }
    }

    /// A kiválasztó UI hívja megnyitáskor: azonnal elindítja a szkennelést,
    /// hogy a hatótávon belüli Linx szenzorok listája gyorsan feltöltődjön
    /// (a Loop amúgy csak ~3 percenként triggerelné a szkennelést).
    public func startScanningForPicker() {
        scanner.resumeScanning()
    }

    public var currentStatusText: String { lastStatus }

    // MARK: - CGMManager metódusok

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        scanner.restartScanIfStale(lastDataAt: lastSampleSentAt)
        scanner.resumeScanning()
        logBackgroundScanDiagnostics(trigger: "heartbeat")
        completion(.noData)
    }

    public func acknowledgeAlert(
        alertIdentifier _: Alert.AlertIdentifier,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    public func getSoundBaseURL() -> URL? { nil }
    public func getSounds() -> [Alert.Sound] { [] }

    /// CGM törlésekor a Loop ezt hívja. Előbb leállítjuk a scannert és
    /// elengedjük a CBCentralManager-t, hogy egy későbbi újra-hozzáadás tiszta
    /// állapotból indulhasson (különben a régi BLE-manager és az új ütközhet a
    /// közös State Restoration ID miatt → "nem támogatja a BLE-t" hiba).
    public func notifyDelegateOfDeletion(completion: @escaping () -> Void) {
        scanner.stop()
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManagerWantsDeletion(self)
            completion()
        }
    }

    // MARK: - Privát

    private func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .receive) {
        cgmManagerDelegate?.deviceManager(
            self,
            logEventForDeviceIdentifier: state.sensorSerial,
            type: type,
            message: message,
            completion: nil
        )
    }

    private func logBackgroundScanDiagnostics(trigger: String) {
        let appState = linxAppStateLabel()

        let sampleAge: String
        if let sentAt = lastSampleSentAt {
            sampleAge = String(format: "%.0fs", Date().timeIntervalSince(sentAt))
        } else {
            sampleAge = "never"
        }
        let advAge: String
        if let advAt = scanner.lastAdvertisementAt {
            advAge = String(format: "%.0fs", Date().timeIntervalSince(advAt))
        } else {
            advAge = "never"
        }
        let restartAge: String
        if let restartAt = scanner.lastScanRestartAt {
            restartAge = String(format: "%.0fs", Date().timeIntervalSince(restartAt))
        } else {
            restartAge = "never"
        }

        let message = """
        Linx bg-scan [\(trigger)]: app=\(appState) scanning=\(scanner.isScanning) \
        lastSample=\(sampleAge) lastAdv=\(advAge) lastRestart=\(restartAge)
        """
        os_log("%{public}@", log: log, type: .info, message)
        logDeviceCommunication(message, type: .connection)
    }

    private func linxAppStateLabel() -> String {
        #if canImport(UIKit)
        let state: UIApplication.State
        if Thread.isMainThread {
            state = UIApplication.shared.applicationState
        } else {
            state = DispatchQueue.main.sync {
                UIApplication.shared.applicationState
            }
        }
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown(\(state.rawValue))"
        }
        #else
        return "unknown"
        #endif
    }

    /// A legutóbbi mérés GlucoseDisplayable-ként (HUD-hoz).
    /// A trend nyilat a SAJÁT számolt értékből vesszük (lastComputedTrend),
    /// nem a megbízhatatlan szenzor trend-bitből.
    private var latestDisplay: LinxGlucoseDisplay? {
        guard let r = latestReading else { return nil }
        return LinxGlucoseDisplay(
            reading: r,
            trend: lastComputedTrend,
            trendRate: lastComputedTrendRate
        )
    }

    /// Az utolsó saját magunk által számolt trend (a delta alapján).
    private var lastComputedTrend: GlucoseTrend = .flat
    /// Az utolsó saját magunk által számolt trend ráta (mg/dL/perc).
    private var lastComputedTrendRate: HKQuantity?

    // MARK: - Simítás (mozgás közbeni pontosság)

    // A broadcast a NYERS értéket küldi, ami mozgás közben ugrálhat (a
    // hivatalos AiDEX app a history-ból simít). Itt minden beérkező nyers
    // értéket bufferelünk, és a Loopnak átadott érték a legutóbbi ~10 perc
    // súlyozott mozgóátlaga (közepes simítás, fix). Kiugrás-szűréssel.
    // 10 perc: elég a zaj kiszűréséhez, de nem ad túl nagy lag-et gyors esésnél.
    private var rawBuffer: [(date: Date, mgdl: Int)] = []
    /// A simítási ablak hossza (másodperc) — közepes: ~10 perc.
    private let smoothingWindow: TimeInterval = 10 * 60
    /// Max reális változás mg/dL per perc — efelé kiugrás.
    private let smoothingMaxRatePerMin: Double = 1.5 * 18.0

    /// Bepufferel egy nyers értéket és visszaadja a simított (súlyozott
    /// mozgóátlag) értéket az aktuális ablakra.
    private func smoothedValue(rawMgdl: Int, at date: Date) -> Int {
        rawBuffer.append((date, rawMgdl))
        // Régi minták eldobása az ablakon kívül.
        let cutoff = date.addingTimeInterval(-smoothingWindow)
        rawBuffer.removeAll { $0.date < cutoff }
        guard rawBuffer.count >= 2 else { return rawMgdl }

        let sorted = rawBuffer.sorted { $0.date < $1.date }
        var weightedSum = 0.0
        var weightTotal = 0.0
        for (i, s) in sorted.enumerated() {
            var w = Double(i + 1) // lineáris súly: újabb = nagyobb
            if i > 0 {
                let prev = sorted[i - 1]
                let dtMin = max(s.date.timeIntervalSince(prev.date) / 60.0, 0.5)
                let rate = abs(Double(s.mgdl - prev.mgdl)) / dtMin
                if rate > smoothingMaxRatePerMin { w *= 0.3 } // kiugrás → kis súly
            }
            weightedSum += Double(s.mgdl) * w
            weightTotal += w
        }
        guard weightTotal > 0 else { return rawMgdl }
        return Int((weightedSum / weightTotal).rounded())
    }

    /// Két egymást követő (Loopnak átadott) érték deltájából számol
    /// mg/dL/perc rátát és abból GlucoseTrend-et — pont mint a Dexcom/Libre.
    /// A küszöbök a Dexcom konvencióit követik.
    private func computeTrend(currentMgdl: Int, currentDate: Date)
        -> (trend: GlucoseTrend, rate: HKQuantity?)
    {
        guard let prevValue = lastSampleValue, let prevAt = lastSampleSentAt else {
            // Nincs előző érték → még nem tudunk trendet számolni.
            return (.flat, nil)
        }
        let elapsedMin = currentDate.timeIntervalSince(prevAt) / 60.0
        guard elapsedMin > 0.5 else {
            // Túl kicsi az időköz → tartsuk meg az előzőt.
            return (lastComputedTrend, lastComputedTrendRate)
        }
        // mg/dL per perc.
        let ratePerMin = Double(currentMgdl - prevValue) / elapsedMin
        let rateQuantity = HKQuantity(
            unit: HKUnit(from: "mg/dL").unitDivided(by: .minute()),
            doubleValue: ratePerMin
        )
        let trend: GlucoseTrend
        switch ratePerMin {
        case let r where r >= 3.0: trend = .upUpUp // ⇈ nagyon gyors emelkedés
        case let r where r >= 2.0: trend = .upUp // ⬆ gyors emelkedés
        case let r where r >= 1.0: trend = .up // ↗ emelkedés
        case let r where r <= -3.0: trend = .downDownDown // ⇊ nagyon gyors esés
        case let r where r <= -2.0: trend = .downDown // ⬇ gyors esés
        case let r where r <= -1.0: trend = .down // ↘ esés
        default: trend = .flat // → stabil (-1..+1)
        }
        return (trend, rateQuantity)
    }
}

// MARK: - LinxScannerDelegate

extension LinxCGMManager: LinxScannerDelegate {
    public func linxScanner(_: LinxScanner, didRead reading: LinxGlucoseReading) {
        // A legfrissebb értéket mindig megtartjuk a HUD-kijelzéshez.
        latestReading = reading

        // SIMÍTÁS: minden beérkező nyers értéket bepufferelünk (még a gate
        // ELŐTT), hogy a simító ablak feltöltődjön a percenkénti csomagokból.
        let rawClamped = min(max(reading.glucoseMgdl, 40), 400)
        let smoothed = smoothedValue(rawMgdl: rawClamped, at: reading.receivedAt)

        // 3 PERCES GATE: a Loopnak csak akkor adunk át új mintát, ha az
        // utolsó átadás óta eltelt ~3 perc. Így a Loop ~3 percenként
        // aktiválódik. Kis toleranciát (10 mp) hagyunk, hogy a ~3 perc körül
        // érkező csomag ne csússzon a következő ablakba.
        if let sentAt = lastSampleSentAt,
           reading.receivedAt.timeIntervalSince(sentAt) < (Self.loopCycleInterval - 10)
        {
            // Még a loopCycleInterval ablakon belül vagyunk → nem aktiváljuk a Loopot
            // (de a nyers érték már bek`erült a simító bufferbe fent).
            updateDelegate(with: .noData)
            return
        }

        let unit = HKUnit(from: "mg/dL")
        // A Loopnak a SIMÍTOTT értéket adjuk át (stabilabb mozgás közben).
        let clamped = min(max(smoothed, 40), 400)
        let quantity = HKQuantity(unit: unit, doubleValue: Double(clamped))

        // SAJÁT trend számítás: az előző és a mostani (Loopnak átadott)
        // érték deltájából — még MIELŐTT frissítenénk a lastSample* mezőket.
        let (computedTrend, computedRate) = computeTrend(
            currentMgdl: clamped,
            currentDate: reading.receivedAt
        )
        lastComputedTrend = computedTrend
        lastComputedTrendRate = computedRate

        lastSampleSentAt = reading.receivedAt
        lastSampleValue = clamped
        mutateState { state in
            state.latestReadingDate = reading.receivedAt
        }

        logDeviceCommunication("Linx didRead \(reading.glucoseMgdl) mg/dL (raw10=\(reading.raw10)) trend=\(computedTrend)")

        let sample = NewGlucoseSample(
            date: reading.receivedAt,
            quantity: quantity,
            condition: nil,
            trend: computedTrend,
            trendRate: computedRate,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: syncIdentifier(for: reading),
            device: device
        )

        updateDelegate(with: .newData([sample]))
    }

    public func linxScanner(_: LinxScanner, didUpdateStatus status: String) {
        lastStatus = status
        stateObservers.forEach { $0.linxStatusDidUpdate(status) }
    }

    public func calibrationForLinxScanner(_: LinxScanner) -> LinxCalibration {
        state.calibration
    }

    public func sensorSerialForLinxScanner(_: LinxScanner) -> String? {
        state.sensorSerial
    }

    public func linxScanner(_: LinxScanner, didDiscoverDeviceNamed advName: String, rssi: Int) {
        let trimmed = advName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previous = nearbyDevicesByName[trimmed]
        nearbyDevicesByName[trimmed] = (rssi: rssi, seen: Date())

        // Csak akkor értesítjük a UI-t, ha új eszköz jelent meg, vagy a
        // jelerősség érdemben (≥4 dBm) változott — így nem pörög feleslegesen.
        let isNew = previous == nil
        let rssiChanged = (previous.map { abs($0.rssi - rssi) >= 4 }) ?? true
        if isNew || rssiChanged {
            let snapshot = nearbyDevices
            let observers = stateObservers
            delegateQueue?.async {
                observers.forEach { $0.linxNearbyDevicesDidUpdate(snapshot) }
            }
        }
    }

    private func syncIdentifier(for reading: LinxGlucoseReading) -> String {
        // Stabil, de mérésenként egyedi azonosító a Loop de-duplikációhoz.
        let secs = Int(reading.receivedAt.timeIntervalSince1970)
        return "Linx-\(state.sensorSerial ?? "any")-\(secs)-\(reading.glucoseMgdl)"
    }

    private func updateDelegate(with result: CGMReadingResult) {
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
        }
    }
}

// MARK: - GlucoseDisplayable

public struct LinxGlucoseDisplay: GlucoseDisplayable {
    private let reading: LinxGlucoseReading
    private let computedTrend: GlucoseTrend
    private let computedTrendRate: HKQuantity?

    public init(
        reading: LinxGlucoseReading,
        trend: GlucoseTrend,
        trendRate: HKQuantity?
    ) {
        self.reading = reading
        computedTrend = trend
        computedTrendRate = trendRate
    }

    public var isStateValid: Bool { true }
    /// A HUD nyilat a saját számolt trendből mutatjuk (nem a szenzor bitből).
    public var trendType: GlucoseTrend? { computedTrend }
    public var trendRate: HKQuantity? { computedTrendRate }
    public var isLocal: Bool { true }
    public var glucoseRangeCategory: GlucoseRangeCategory? { nil }
}
