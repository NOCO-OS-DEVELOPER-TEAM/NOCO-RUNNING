import SwiftUI

struct WeatherGlyph: View {
    var symbol: String
    var temperatureC: Double?

    var body: some View {
        HStack(spacing: 8) {
            glyph
                .frame(width: 28, height: 28)
            if let temperatureC {
                Text("\(Int(temperatureC.rounded()))°")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var glyph: some View {
        switch normalized {
        case "sun", "clear":
            Image(systemName: "sun.max.fill")
                .foregroundStyle(NocoTheme.sun)
                .symbolEffect(.pulse, options: .repeating)
        case "rain":
            Image(systemName: "cloud.rain.fill")
                .foregroundStyle(NocoTheme.aqua)
        case "cloud", "cloudy":
            Image(systemName: "cloud.fill")
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: sinOffset)
        case "wind":
            Image(systemName: "wind")
                .foregroundStyle(NocoTheme.mist)
        default:
            Image(systemName: "cloud.sun.fill")
                .foregroundStyle(NocoTheme.sun)
        }
    }

    private var normalized: String {
        symbol.lowercased()
    }

    private var sinOffset: CGFloat {
        0
    }

    private var accessibility: String {
        if let temperatureC {
            return "Wetter \(symbol), \(Int(temperatureC.rounded())) Grad"
        }
        return "Wetter \(symbol)"
    }
}
