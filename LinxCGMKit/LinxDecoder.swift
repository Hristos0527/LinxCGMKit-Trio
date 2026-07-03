import Foundation

/// Egy dekódolt Linx mérés.
public struct LinxGlucoseReading: Equatable {
    public let receivedAt: Date
    public let glucoseMgdl: Int
    public let trend: Int // 0..3 (idx7 >>10 &3)
    public let raw10: Int // nyers glu10 (kalibrációhoz)
    public let serial: String?
    public let rawHex: String

    public var glucoseMmol: Double { Double(glucoseMgdl) / 18.0 }
}

/// Egy kalibrációs pont: a nyers glu10 + a felhasználó által megadott
/// referencia vércukor (mmol/L). A plugin state-jében perzisztálva.
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

/// A kétpontos kalibráció: mmol = calA * glu10 + calB.
/// A bevált, egész nap tesztelt logika 1:1 átemelve.
public struct LinxCalibration: Equatable {
    // ✅ BEVÁLT ALAPGÖRBE (2026-06-18). A korábbi, jól működő app két valós
    // referenciaponttal kalibrált, és ez egy napon át pontos volt a gyári
    // Linx görbéhez igazítva:
    //   nyers 108 -> 5.8 mmol
    //   nyers 134 -> 7.5 mmol
    //   Aktív görbe: mmol = 0.06538 * nyers - 1.2615
    // Ellenőrzés: glu10≈137 -> 0.06538*137-1.2615 = 7.69 mmol ≈ a gyári Linx 7.8.
    //
    // A korábbi 0.01667-es alapmeredekség kb. 4× laposabb volt → mindent
    // lenyomott (5.6-ot mutatott 7.8 helyett). A nyers dekódolás (glu10) végig
    // helyes volt; csak ez az alapgörbe volt rossz. A standalone LinxReader
    // appban ugyanezt a görbét égettük be.
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

    /// Új referenciapont hozzáadása. A 2 legutóbbit tartjuk meg.
    public mutating func addPoint(glu10: Int, mmol: Double) {
        points.append(LinxCalPoint(glu10: glu10, mmol: mmol))
        if points.count > 2 { points = Array(points.suffix(2)) }
        recompute()
    }

    /// Visszaállítás a gyári alaphangolásra.
    public mutating func reset() {
        points = []
        calA = LinxCalibration.defaultCalA
        calB = LinxCalibration.defaultCalB
    }

    /// A pontokból újraszámolja calA/calB-t.
    ///  - 2 pont, eltérő glu10  -> kétpontos illesztés (meredekség + eltolás)
    ///  - 1 pont (vagy 2 azonos glu10) -> egypontos: meredekséget tartjuk,
    ///    csak az eltolást igazítjuk, hogy a ponton pontos legyen
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

    /// mmol kiszámítása a nyers glu10-ből.
    public func mmol(forRaw10 glu10: Int) -> Double {
        calA * Double(glu10) + calB
    }
}

public enum LinxDecoder {
    public static func mmolToMgdl(_ mmol: Double) -> Int { Int((mmol * 18.0).rounded()) }

    /// Visszaadja a dekódolt mérést, vagy nil, ha bemelegedés / rossz hossz.
    /// A kalibrációt kívülről kapja (a manager state-jéből).
    public static func decode(
        manufacturerData mfg: Data,
        advName: String,
        calibration: LinxCalibration
    ) -> LinxGlucoseReading? {
        let b = [UInt8](mfg)
        guard b.count >= 27 else { return nil }

        func le16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }

        // ── Legfrissebb nyers glükóz (idx 7-8) ──
        let raw16 = le16(7)
        // Bemelegedés-szentinel: az alsó 16 bit 0xFFFF
        guard raw16 != 0xFFFF else { return nil }

        let glu10 = raw16 & 0x3FF
        let trend = (raw16 >> 10) & 3

        // ── Kalibráció mmol → mg/dL ──
        let mmol = calibration.mmol(forRaw10: glu10)
        let bg = mmolToMgdl(mmol)

        // Józansági szűrő (1.5–30 mmol ~ 27–540 mg/dL)
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
