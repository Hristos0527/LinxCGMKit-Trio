import Foundation
import LoopKit

public struct LinxCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    /// A figyelt szenzor sorozatszáma (pl. "LinX-2222296PN2"). nil = bármelyik.
    public var sensorSerial: String?

    /// Kétpontos kalibráció (meredekség + eltolás + a rögzített pontok).
    public var calibration: LinxCalibration

    /// Az utolsó dekódolt mérés ideje (státusz-kijelzéshez).
    public var latestReadingDate: Date?

    /// Feltöltsük-e a Nightscoutra (Loop "Upload Readings").
    public var uploadReadings: Bool = true

    public init(
        sensorSerial: String? = nil,
        calibration: LinxCalibration = LinxCalibration(),
        latestReadingDate: Date? = nil,
        uploadReadings: Bool = true
    ) {
        self.sensorSerial = sensorSerial
        self.calibration = calibration
        self.latestReadingDate = latestReadingDate
        self.uploadReadings = uploadReadings
    }

    public init(rawValue: RawValue) {
        sensorSerial = rawValue["sensorSerial"] as? String
        latestReadingDate = rawValue["latestReadingDate"] as? Date
        uploadReadings = rawValue["uploadReadings"] as? Bool ?? true

        var cal = LinxCalibration()
        if let a = rawValue["calA"] as? Double { cal.calA = a }
        if let b = rawValue["calB"] as? Double { cal.calB = b }
        if let ptsData = rawValue["calPoints"] as? Data,
           let pts = try? JSONDecoder().decode([LinxCalPoint].self, from: ptsData)
        {
            cal.points = pts
        }
        calibration = cal
    }

    public var rawValue: RawValue {
        var raw: RawValue = [:]
        raw["sensorSerial"] = sensorSerial
        raw["latestReadingDate"] = latestReadingDate
        raw["uploadReadings"] = uploadReadings
        raw["calA"] = calibration.calA
        raw["calB"] = calibration.calB
        if let ptsData = try? JSONEncoder().encode(calibration.points) {
            raw["calPoints"] = ptsData
        }
        return raw
    }
}
