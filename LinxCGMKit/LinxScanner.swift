import CoreBluetooth
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

public protocol LinxScannerDelegate: AnyObject {
    /// Új, dekódolható mérés érkezett a megadott (vagy bármelyik, ha nincs
    /// szűrés) szenzortól.
    func linxScanner(_ scanner: LinxScanner, didRead reading: LinxGlucoseReading)
    /// A szkenner állapota változott (log/diagnosztika).
    func linxScanner(_ scanner: LinxScanner, didUpdateStatus status: String)
    /// A scanner kéri az aktuális kalibrációt a dekódoláshoz.
    func calibrationForLinxScanner(_ scanner: LinxScanner) -> LinxCalibration
    /// A scanner kéri a beállított szenzor-sorozatszámot (nil = bármelyik).
    func sensorSerialForLinxScanner(_ scanner: LinxScanner) -> String?
    /// Hatótávon belül érzékelt Linx szenzor (a kiválasztó listához).
    /// advName = a hirdetett teljes név ("LinX-..."), rssi = jelerősség.
    func linxScanner(_ scanner: LinxScanner, didDiscoverDeviceNamed advName: String, rssi: Int)
}

public final class LinxScanner: NSObject {
    public weak var delegate: LinxScannerDelegate?

    /// A Linx szenzor által hirdetett service-UUID (16-bit SIG: 181F).
    public static let linxServiceUUID = CBUUID(string: "181F")

    /// Háttérben ennyi csend után újraindítjuk a scant (watchdog).
    public static let backgroundScanStaleInterval: TimeInterval = 4 * 60

    /// A gyártói ID a manufacturer data első 2 bájtja, little-endian (Nordic).
    private let expectedManufacturerID: UInt16 = 0x0059

    private let log = OSLog(subsystem: "com.linxcgmkit", category: "LinxScanner")

    private var central: CBCentralManager?
    private var lastSeen: [UUID: Date] = [:]

    public private(set) var isScanning: Bool = false
    /// Utolsó érvényes Linx manufacturer advertisement ideje (dekódolástól függetlenül).
    public private(set) var lastAdvertisementAt: Date?
    /// Utolsó háttér scan-kick / watchdog restart ideje.
    public private(set) var lastScanRestartAt: Date?

    override public init() {
        super.init()
        ensureCentral()
    }

    /// A CBCentralManager LUSTA, egyszeri létrehozása.
    /// Fontos: CGM törlés→újra-hozzáadás után az új LinxCGMManager új scannert
    /// hoz létre. Ha ilyenkor azonnal új CBCentralManager-t csinálnánk ugyanazzal
    /// a State Restoration ID-vel, miközben a régi belső BLE-állapot még "él",
    /// a CoreBluetooth összezavarodhat és hibás állapotba (akár .unsupported-szerű)
    /// kerülhet. Ezért biztosítjuk, hogy mindig csak EGY managerünk legyen, és
    /// az átmeneti (.unknown/.resetting) állapotokat türelmesen kezeljük.
    private func ensureCentral() {
        guard central == nil else { return }
        // NINCS State Restoration ID: így a manager minden alkalommal tisztán
        // jön létre, és a CGM törlés→újra-hozzáadás sosem akad össze.
        // (A Loop a pumpa-kommunikáció miatt amúgy is gyakran ébren tartja az
        //  appot, így a háttér-olvasás a gyakorlatban továbbra is működik.)
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    public func resumeScanning() {
        ensureCentral()
        switch central?.state {
        case .poweredOn:
            if isAppInBackground, isScanning {
                // Háttérben a Loop heartbeat-jén frissítjük a scan ciklust.
                restartScan(reason: "heartbeat kick")
            } else {
                startScan()
            }
        case .none,
             .some(.resetting),
             .some(.unknown):
            // Átmeneti állapot — a centralManagerDidUpdateState úgyis elindítja
            // a scant, amint .poweredOn lesz. Itt nem kell tenni semmit.
            notify("Bluetooth starting...")
        default:
            break
        }
    }

    /// Ha háttérben túl régóta nincs friss adat, stopScan → startScan.
    public func restartScanIfStale(lastDataAt: Date?) {
        guard isAppInBackground else { return }
        let reference = [lastDataAt, lastAdvertisementAt]
            .compactMap { $0 }
            .max()
        if let reference, Date().timeIntervalSince(reference) < Self.backgroundScanStaleInterval {
            return
        }
        restartScan(reason: "watchdog stale")
    }

    private func startScan() {
        guard let central = central, central.state == .poweredOn else { return }
        // Háttérben AllowDuplicatesKey: true — iOS throttling ellen minden
        // advertisement callbacket megkapunk; a 3 perces gate szűri a Loop kimenetet.
        let allowDuplicates = isAppInBackground
        central.scanForPeripherals(
            withServices: [Self.linxServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
        isScanning = true
        logScanDiagnostics(context: allowDuplicates ? "startScan(bg dup=1)" : "startScan(fg dup=0)")
        notify(allowDuplicates ? "Scan fut (181F, bg duplicates)..." : "Scan fut (181F)...")
    }

    private func restartScan(reason: String) {
        guard let central = central, central.state == .poweredOn else { return }
        if isScanning {
            central.stopScan()
            isScanning = false
        }
        lastScanRestartAt = Date()
        startScan()
        logScanDiagnostics(context: "restart:\(reason)")
    }

    private var isAppInBackground: Bool {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return UIApplication.shared.applicationState != .active
        }
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState != .active
        }
        #else
        return false
        #endif
    }

    private func logScanDiagnostics(context: String) {
        let bg = isAppInBackground
        let advAge: String
        if let lastAdv = lastAdvertisementAt {
            advAge = String(format: "%.0fs", Date().timeIntervalSince(lastAdv))
        } else {
            advAge = "never"
        }
        let restartAge: String
        if let lastRestart = lastScanRestartAt {
            restartAge = String(format: "%.0fs", Date().timeIntervalSince(lastRestart))
        } else {
            restartAge = "never"
        }
        let msg = "Linx scan \(context) scanning=\(isScanning) bg=\(bg) lastAdv=\(advAge) lastRestart=\(restartAge)"
        os_log("%{public}@", log: log, type: .info, msg)
    }

    /// A scan leállítása és a manager elengedése (CGM törlésekor hívjuk).
    /// Ez biztosítja, hogy a régi CBCentralManager felszabaduljon, mielőtt
    /// egy újra-hozzáadás új managert hozna létre ugyanazzal a restore ID-vel.
    public func stop() {
        if let central = central, central.state == .poweredOn, isScanning {
            central.stopScan()
        }
        isScanning = false
        central?.delegate = nil
        central = nil
    }

    private func notify(_ s: String) {
        delegate?.linxScanner(self, didUpdateStatus: s)
    }
}

// MARK: - CBCentralManagerDelegate

extension LinxScanner: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            notify("Bluetooth ON — scan starting (181F)")
            startScan()
        case .poweredOff:
            isScanning = false
            notify("Bluetooth is off")
        case .unauthorized:
            notify("No Bluetooth permission")
        case .unsupported:
            notify("Device does not support BLE")
        case .resetting:
            // A BLE-rendszer épp újraindul (pl. CGM törlés→újra-hozzáadás után).
            // NEM végleges hiba — várunk, amíg .poweredOn lesz.
            isScanning = false
            notify("Bluetooth restarting, waiting...")
        case .unknown:
            notify("Bluetooth state loading...")
        @unknown default:
            notify("Bluetooth state: \(central.state.rawValue)")
        }
    }

    public func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""

        // Manufacturer data kiolvasása
        guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }

        let bytes = [UInt8](mfg)
        let mfgID: UInt16 = bytes.count >= 2
            ? UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            : 0

        // Biztonsági szűrés: csak Nordic (0x0059) 27-bájtos Linx csomag.
        guard mfgID == expectedManufacturerID, bytes.count == 27 else { return }
        lastAdvertisementAt = Date()

        // Kiválasztó lista: CSAK olyan eszközt jelentünk a UI-nak, aminek a
        // nevében szerepel a "Linx" (más BT-eszköz sosem). Ez a sorozatszám-
        // szűrés ELŐTT fut, hogy minden hatótávon belüli Linx megjelenjen.
        if advName.lowercased().contains("linx") {
            delegate?.linxScanner(self, didDiscoverDeviceNamed: advName, rssi: RSSI.intValue)
        }

        // Sorozatszám-szűrés: ha a felhasználó megadott egyet, csak azt fogadjuk.
        if let wanted = delegate?.sensorSerialForLinxScanner(self),
           !wanted.isEmpty
        {
            // Részleges egyezés is elég (a hirdetett név "LinX-2222296PN2" formátum).
            if !advName.isEmpty, !advName.contains(wanted) {
                return
            }
        }

        // Throttle: 1 mp eszközönként
        let now = Date()
        if let last = lastSeen[peripheral.identifier], now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastSeen[peripheral.identifier] = now

        // Dekódolás az aktuális kalibrációval
        let cal = delegate?.calibrationForLinxScanner(self) ?? LinxCalibration()
        if let reading = LinxDecoder.decode(manufacturerData: mfg, advName: advName, calibration: cal) {
            delegate?.linxScanner(self, didRead: reading)
        }
    }
}
