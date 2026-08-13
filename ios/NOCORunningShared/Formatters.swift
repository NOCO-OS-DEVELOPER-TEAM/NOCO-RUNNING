import Foundation

public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric
    case imperial

    public var distanceLabel: String { self == .metric ? "km" : "mi" }
    public var speedLabel: String { self == .metric ? "km/h" : "mph" }
    public var paceLabel: String { self == .metric ? "min/km" : "min/mi" }
}

public enum RunFormatters: Sendable {
    public static func distance(_ meters: Double, units: UnitSystem) -> String {
        let value = units == .metric ? meters / 1000 : meters / 1609.344
        if value < 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.1f", value)
    }

    public static func distanceWithUnit(_ meters: Double, units: UnitSystem) -> String {
        "\(distance(meters, units: units)) \(units.distanceLabel)"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    public static func pace(secondsPerKm: Double?, units: UnitSystem) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else {
            return "–"
        }
        let seconds = units == .metric ? secondsPerKm : secondsPerKm * 1.609344
        return paceClock(seconds) + " " + units.paceLabel
    }

    public static func paceClock(_ secondsPerUnit: Double) -> String {
        guard secondsPerUnit.isFinite, secondsPerUnit > 0, secondsPerUnit < 3600 else { return "–" }
        let total = Int(secondsPerUnit.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func speed(metersPerSecond: Double, units: UnitSystem) -> String {
        guard metersPerSecond.isFinite, metersPerSecond > 0.15 else { return "0,0" }
        let value = units == .metric ? metersPerSecond * 3.6 : metersPerSecond * 2.236936
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    public static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "–" }
        return "\(Int(bpm.rounded()))"
    }

    public static func calories(_ kcal: Double?) -> String {
        guard let kcal, kcal > 0 else { return "–" }
        return "\(Int(kcal.rounded()))"
    }

    public static func elevation(_ meters: Double) -> String {
        guard meters > 0.5 else { return "0 m" }
        return "\(Int(meters.rounded())) m"
    }

    public static func relativeDate(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM y")
        }
        return formatter.string(from: date)
    }
}

public enum PaceMath: Sendable {
    public static func secondsPerKm(distanceMeters: Double, duration: TimeInterval) -> Double? {
        guard distanceMeters > 20, duration > 1 else { return nil }
        return duration / (distanceMeters / 1000)
    }

    public static func metersPerSecond(paceSecondsPerKm: Double) -> Double? {
        guard paceSecondsPerKm > 0 else { return nil }
        return 1000 / paceSecondsPerKm
    }
}
