import SwiftUI

enum NocoTheme {
    static let ink = Color(red: 0.027, green: 0.031, blue: 0.047)
    static let inkElevated = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let mist = Color.white.opacity(0.72)
    static let aqua = Color(red: 0.24, green: 0.88, blue: 0.76)
    static let violet = Color(red: 0.48, green: 0.42, blue: 1.0)
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.54)
    static let sun = Color(red: 1.0, green: 0.78, blue: 0.38)

    static let heroFont: Font = .system(size: 56, weight: .semibold, design: .rounded)
    static let metricFont: Font = .system(size: 34, weight: .semibold, design: .rounded)
    static let captionFont: Font = .system(size: 13, weight: .medium, design: .rounded)

    static var aurora: LinearGradient {
        LinearGradient(
            colors: [aqua, violet, coral],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var auroraSoft: LinearGradient {
        LinearGradient(
            colors: [aqua.opacity(0.55), violet.opacity(0.4), coral.opacity(0.35)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func paceTint(secondsPerKm: Double?) -> Color {
        guard let secondsPerKm else { return mist }
        switch secondsPerKm {
        case ..<300: return coral
        case ..<360: return sun
        case ..<420: return aqua
        default: return violet.opacity(0.9)
        }
    }
}

enum NocoMotion {
    static let snappy = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let soft = Animation.spring(response: 0.55, dampingFraction: 0.9)
    static let count = Animation.easeOut(duration: 0.7)
}
