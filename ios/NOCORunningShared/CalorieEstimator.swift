import Foundation

public enum CalorieEstimator: Sendable {
    /// ACSM-inspired running estimate. Uses moving time, not wall-clock pauses.
    public static func kcal(distanceMeters: Double, duration: TimeInterval, weightKg: Double?) -> Double {
        let kg = max(40, weightKg ?? 72)
        let hours = max(duration, 1) / 3600
        let kmh = distanceMeters / max(duration, 1) * 3.6
        let speed = min(max(kmh, 5), 22)
        let met = 1.6 + speed * 0.95
        return met * kg * hours
    }
}
