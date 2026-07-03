import Foundation
import LoopKit

public struct LinxCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    /// Serial number of the monitored sensor (e.g. "LinX-2222296PN2"). nil = any.
    public var sensorSerial: String?

    /// Two-point calibration (slope + offset + recorded points).
    public var calibration: LinxCalibration

    /// Time of the last decoded reading (for status display).
    public var latestReadingDate: Date?

    /// Whether to upload to Nightscout (Loop "Upload Readings").
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
