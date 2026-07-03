import CoreBluetooth
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

public protocol LinxScannerDelegate: AnyObject {
    /// A new decodable reading arrived from the specified (or any, if not
    /// filtered) sensor.
    func linxScanner(_ scanner: LinxScanner, didRead reading: LinxGlucoseReading)
    /// Scanner state changed (log/diagnostics).
    func linxScanner(_ scanner: LinxScanner, didUpdateStatus status: String)
    /// Scanner requests current calibration for decoding.
    func calibrationForLinxScanner(_ scanner: LinxScanner) -> LinxCalibration
    /// Scanner requests configured sensor serial number (nil = any).
    func sensorSerialForLinxScanner(_ scanner: LinxScanner) -> String?
    /// Linx sensor detected in range (for the picker list).
    /// advName = advertised full name ("LinX-..."), rssi = signal strength.
    func linxScanner(_ scanner: LinxScanner, didDiscoverDeviceNamed advName: String, rssi: Int)
}

public final class LinxScanner: NSObject {
    public weak var delegate: LinxScannerDelegate?

    /// Service UUID advertised by the Linx sensor (16-bit SIG: 181F).
    public static let linxServiceUUID = CBUUID(string: "181F")

    /// In background, restart scan after this much silence (watchdog).
    public static let backgroundScanStaleInterval: TimeInterval = 4 * 60

    /// Manufacturer ID is the first 2 bytes of manufacturer data, little-endian (Nordic).
    private let expectedManufacturerID: UInt16 = 0x0059

    private let log = OSLog(subsystem: "com.linxcgmkit", category: "LinxScanner")

    private var central: CBCentralManager?
    private var lastSeen: [UUID: Date] = [:]

    public private(set) var isScanning: Bool = false
    /// Time of last valid Linx manufacturer advertisement (regardless of decode).
    public private(set) var lastAdvertisementAt: Date?
    /// Time of last background scan kick / watchdog restart.
    public private(set) var lastScanRestartAt: Date?

    override public init() {
        super.init()
        ensureCentral()
    }

    /// LAZY, one-time creation of CBCentralManager.
    /// Important: after CGM delete→re-add, the new LinxCGMManager creates a new scanner.
    /// If we immediately created a new CBCentralManager with the same State Restoration ID
    /// while the old internal BLE state is still "alive", CoreBluetooth can get confused
    /// and end up in a bad state (possibly .unsupported-like). So we ensure we always have
    /// only ONE manager, and handle transient (.unknown/.resetting) states patiently.
    private func ensureCentral() {
        guard central == nil else { return }
        // NO State Restoration ID: the manager is created cleanly every time, and
        // CGM delete→re-add never collides.
        // (Loop keeps the app awake often anyway for pump communication, so background
        //  reading still works in practice.)
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
                // In background, refresh the scan cycle on Loop heartbeat.
                restartScan(reason: "heartbeat kick")
            } else {
                startScan()
            }
        case .none,
             .some(.resetting),
             .some(.unknown):
            // Transient state — centralManagerDidUpdateState will start scanning
            // once .poweredOn. Nothing to do here.
            notify("Bluetooth starting...")
        default:
            break
        }
    }

    /// In background, if there has been no fresh data for too long, stopScan → startScan.
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
        // In background AllowDuplicatesKey: true — against iOS throttling we get every
        // advertisement callback; the 3-minute gate filters Loop output.
        let allowDuplicates = isAppInBackground
        central.scanForPeripherals(
            withServices: [Self.linxServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
        isScanning = true
        logScanDiagnostics(context: allowDuplicates ? "startScan(bg dup=1)" : "startScan(fg dup=0)")
        notify(allowDuplicates ? "Scan running (181F, bg duplicates)..." : "Scan running (181F)...")
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

    /// Stop scanning and release the manager (called on CGM deletion).
    /// Ensures the old CBCentralManager is freed before re-add creates a new one
    /// with the same restore ID.
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
            // BLE stack is restarting (e.g. after CGM delete→re-add).
            // NOT a permanent error — wait until .poweredOn.
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

        // Read manufacturer data
        guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }

        let bytes = [UInt8](mfg)
        let mfgID: UInt16 = bytes.count >= 2
            ? UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            : 0

        // Safety filter: Nordic (0x0059) 27-byte Linx packet only.
        guard mfgID == expectedManufacturerID, bytes.count == 27 else { return }
        lastAdvertisementAt = Date()

        // Picker list: report to the UI ONLY devices whose name contains "Linx"
        // (never other BT devices). This runs BEFORE serial filtering so every
        // in-range Linx appears.
        if advName.lowercased().contains("linx") {
            delegate?.linxScanner(self, didDiscoverDeviceNamed: advName, rssi: RSSI.intValue)
        }

        // Serial filter: if the user specified one, accept only that sensor.
        if let wanted = delegate?.sensorSerialForLinxScanner(self),
           !wanted.isEmpty
        {
            // Partial match is enough (advertised name is "LinX-2222296PN2" format).
            if !advName.isEmpty, !advName.contains(wanted) {
                return
            }
        }

        // Throttle: 1 s per device
        let now = Date()
        if let last = lastSeen[peripheral.identifier], now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastSeen[peripheral.identifier] = now

        // Decode with current calibration
        let cal = delegate?.calibrationForLinxScanner(self) ?? LinxCalibration()
        if let reading = LinxDecoder.decode(manufacturerData: mfg, advName: advName, calibration: cal) {
            delegate?.linxScanner(self, didRead: reading)
        }
    }
}
