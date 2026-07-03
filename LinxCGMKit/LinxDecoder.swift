import Foundation

/// A decoded Linx reading.
public struct LinxGlucoseReading: Equatable {
    public let receivedAt: Date
    public let glucoseMgdl: Int
    public let trend: Int // 0..3 (idx7 >>10 &3)
    public let raw10: Int // raw glu10 (for calibration)
    public let serial: String?
    public let rawHex: String

    public var glucoseMmol: Double { Double(glucoseMgdl) / 18.0 }
}

/// A calibration point: raw glu10 + user-provided reference blood glucose
/// (mmol/L). Persisted in the plugin state.
public struct LinxCalPoint: Codable, Equatable {
    public let glu10: Int
    public let mmol: Double
    public let date: Date

    public init(glu10: Int, mmol: Double, date: Date = Date()) {
        self.glu10 = glu10
        self.mmol = mmol
        self.date = date
    }
}

/// Two-point calibration: mmol = calA * glu10 + calB.
/// Proven, full-day-tested logic carried over 1:1.
public struct LinxCalibration: Equatable {
    // ✅ PROVEN BASE CURVE (2026-06-18). The previous, working app was calibrated
    // with two real reference points, and this matched the factory Linx curve
    // accurately for a full day:
    //   raw 108 -> 5.8 mmol
    //   raw 134 -> 7.5 mmol
    //   Active curve: mmol = 0.06538 * raw - 1.2615
    // Check: glu10≈137 -> 0.06538*137-1.2615 = 7.69 mmol ≈ factory Linx 7.8.
    //
    // The previous 0.01667 base slope was ~4× flatter → everything was
    // suppressed (showed 5.6 instead of 7.8). Raw decoding (glu10) was correct
    // all along; only this base curve was wrong. The standalone LinxReader app
    // baked in the same curve.
    public static let defaultCalA: Double = 0.06538
    public static let defaultCalB: Double = -1.2615

    public var calA: Double
    public var calB: Double
    public var points: [LinxCalPoint]

    public init(
        calA: Double = LinxCalibration.defaultCalA,
        calB: Double = LinxCalibration.defaultCalB,
        points: [LinxCalPoint] = []
    ) {
        self.calA = calA
        self.calB = calB
        self.points = points
    }

    /// Add a new reference point. We keep the 2 most recent.
    public mutating func addPoint(glu10: Int, mmol: Double) {
        points.append(LinxCalPoint(glu10: glu10, mmol: mmol))
        if points.count > 2 { points = Array(points.suffix(2)) }
        recompute()
    }

    /// Reset to factory default calibration.
    public mutating func reset() {
        points = []
        calA = LinxCalibration.defaultCalA
        calB = LinxCalibration.defaultCalB
    }

    /// Recomputes calA/calB from the points.
    ///  - 2 points, different glu10  -> two-point fit (slope + offset)
    ///  - 1 point (or 2 identical glu10) -> single-point: keep slope,
    ///    adjust offset so the point is exact
    public mutating func recompute() {
        if points.count >= 2, points[0].glu10 != points[1].glu10 {
            let (p1, p2) = (points[0], points[1])
            let a = (p2.mmol - p1.mmol) / Double(p2.glu10 - p1.glu10)
            let b = p1.mmol - a * Double(p1.glu10)
            calA = a
            calB = b
        } else if let p = points.last {
            calB = p.mmol - calA * Double(p.glu10)
        }
    }

    /// Compute mmol from raw glu10.
    public func mmol(forRaw10 glu10: Int) -> Double {
        calA * Double(glu10) + calB
    }
}

public enum LinxDecoder {
    public static func mmolToMgdl(_ mmol: Double) -> Int { Int((mmol * 18.0).rounded()) }

    /// Returns the decoded reading, or nil on warmup / bad length.
    /// Calibration is supplied externally (from manager state).
    public static func decode(
        manufacturerData mfg: Data,
        advName: String,
        calibration: LinxCalibration
    ) -> LinxGlucoseReading? {
        let b = [UInt8](mfg)
        guard b.count >= 27 else { return nil }

        func le16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }

        // ── Latest raw glucose (idx 7-8) ──
        let raw16 = le16(7)
        // Warmup sentinel: lower 16 bits are 0xFFFF
        guard raw16 != 0xFFFF else { return nil }

        let glu10 = raw16 & 0x3FF
        let trend = (raw16 >> 10) & 3

        // ── Calibration mmol → mg/dL ──
        let mmol = calibration.mmol(forRaw10: glu10)
        let bg = mmolToMgdl(mmol)

        // Sanity filter (1.5–30 mmol ~ 27–540 mg/dL)
        guard (27 ... 540).contains(bg) else { return nil }

        let hex = b.map { String(format: "%02X", $0) }.joined()

        return LinxGlucoseReading(
            receivedAt: Date(),
            glucoseMgdl: bg,
            trend: trend,
            raw10: glu10,
            serial: advName.isEmpty ? nil : advName,
            rawHex: hex
        )
    }
}
