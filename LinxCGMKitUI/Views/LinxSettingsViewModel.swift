import Combine
import Foundation
import LinxCGMKit
import LoopKit
import LoopKitUI

class LinxSettingsViewModel: ObservableObject, LinxStateObserver {
    private(set) var cgmManager: LinxCGMManager
    private var displayGlucosePreference: DisplayGlucosePreference

    @Published var sensorSerial: String
    /// Linx sensors detected in range (for the picker list).
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

    /// Raw glu10 value from the latest reading (for calibration).
    var currentRaw10: Int? { cgmManager.latestReading?.raw10 }

    // MARK: - Actions

    func saveSerial() {
        cgmManager.setSensorSerial(sensorSerial.trimmingCharacters(in: .whitespaces))
    }

    /// Persist the sensor chosen from the picker list: we only filter to it,
    /// no connection is needed (we read from Linx advertisements). We save the
    /// full advertised name so the scanner filters to exactly this one sensor.
    func selectDevice(_ device: LinxNearbyDevice) {
        sensorSerial = device.name
        cgmManager.setSensorSerial(device.name)
    }

    /// Called when opening settings: starts scanning and loads the currently
    /// known sensor list.
    func startScanning() {
        cgmManager.startScanningForPicker()
        nearbyDevices = cgmManager.nearbyDevices
    }

    /// Record a new calibration point with the given reference mmol/L against
    /// the CURRENT raw glu10 value.
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
