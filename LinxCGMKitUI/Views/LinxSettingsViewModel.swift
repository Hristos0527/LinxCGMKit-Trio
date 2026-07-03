import Combine
import Foundation
import LinxCGMKit
import LoopKit
import LoopKitUI

class LinxSettingsViewModel: ObservableObject, LinxStateObserver {
    private(set) var cgmManager: LinxCGMManager
    private var displayGlucosePreference: DisplayGlucosePreference

    @Published var sensorSerial: String
    /// Hatótávon belül érzékelt Linx szenzorok (a kiválasztó listához).
    @Published var nearbyDevices: [LinxNearbyDevice] = []
    @Published var statusText: String
    @Published var latestGlucoseText: String
    @Published var calA: Double
    @Published var calB: Double
    @Published var calPoints: [LinxCalPoint]

    init(cgmManager: LinxCGMManager, displayGlucosePreference: DisplayGlucosePreference) {
        self.cgmManager = cgmManager
        self.displayGlucosePreference = displayGlucosePreference

        let st = cgmManager.state
        sensorSerial = st.sensorSerial ?? ""
        calA = st.calibration.calA
        calB = st.calibration.calB
        calPoints = st.calibration.points
        statusText = cgmManager.currentStatusText
        latestGlucoseText = Self.glucoseText(cgmManager.latestReading)
        nearbyDevices = cgmManager.nearbyDevices

        cgmManager.addStateObserver(self)
    }

    deinit {
        cgmManager.removeStateObserver(self)
    }

    static func glucoseText(_ r: LinxGlucoseReading?) -> String {
        guard let r = r else { return "—" }
        return String(format: "%.1f mmol/L (%d mg/dL)", r.glucoseMmol, r.glucoseMgdl)
    }

    /// A legutóbbi mérés nyers glu10 értéke (kalibrációhoz).
    var currentRaw10: Int? { cgmManager.latestReading?.raw10 }

    // MARK: - Akciók

    func saveSerial() {
        cgmManager.setSensorSerial(sensorSerial.trimmingCharacters(in: .whitespaces))
    }

    /// A kiválasztó listából választott szenzor rögzítése: csak szűrünk rá,
    /// csatlakozni nem kell (a Linx hirdetésből olvasunk). A teljes hirdetett
    /// nevet mentjük el, így pontosan erre az egy szenzorra szűr a scanner.
    func selectDevice(_ device: LinxNearbyDevice) {
        sensorSerial = device.name
        cgmManager.setSensorSerial(device.name)
    }

    /// A beállítások megnyitásakor hívjuk: elindítja a szkennelést és
    /// betölti az aktuálisan ismert szenzorlistát.
    func startScanning() {
        cgmManager.startScanningForPicker()
        nearbyDevices = cgmManager.nearbyDevices
    }

    /// Új kalibrációs pont rögzítése a megadott referencia mmol-lal,
    /// a JELENLEGI nyers glu10 értékre.
    func addCalibration(refMmol: Double) {
        guard let raw10 = currentRaw10 else { return }
        cgmManager.addCalibration(glu10: raw10, mmol: refMmol)
        refresh()
    }

    func resetCalibration() {
        cgmManager.resetCalibration()
        refresh()
    }

    private func refresh() {
        let st = cgmManager.state
        calA = st.calibration.calA
        calB = st.calibration.calB
        calPoints = st.calibration.points
    }

    // MARK: - LinxStateObserver

    func linxStateDidUpdate(_ state: LinxCGMManagerState) {
        DispatchQueue.main.async {
            self.calA = state.calibration.calA
            self.calB = state.calibration.calB
            self.calPoints = state.calibration.points
            if self.sensorSerial.isEmpty, let s = state.sensorSerial { self.sensorSerial = s }
            self.latestGlucoseText = Self.glucoseText(self.cgmManager.latestReading)
        }
    }

    func linxStatusDidUpdate(_ status: String) {
        DispatchQueue.main.async {
            self.statusText = status
            self.latestGlucoseText = Self.glucoseText(self.cgmManager.latestReading)
        }
    }

    func linxNearbyDevicesDidUpdate(_ devices: [LinxNearbyDevice]) {
        DispatchQueue.main.async {
            self.nearbyDevices = devices
        }
    }
}
