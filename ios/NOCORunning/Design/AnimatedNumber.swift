import SwiftUI

struct AnimatedNumber: View {
    var value: Double
    var format: String = "%.2f"
    var font: Font = NocoTheme.heroFont
    var comma: Bool = true

    var body: some View {
        Text(display)
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(NocoMotion.count, value: value)
    }

    private var display: String {
        let raw = String(format: format, value)
        return comma ? raw.replacingOccurrences(of: ".", with: ",") : raw
    }
}

struct MetricStack: View {
    var label: String
    var value: String
    var emphasis: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(NocoTheme.mist.opacity(0.7))
            Text(value)
                .font(emphasis ? NocoTheme.heroFont : NocoTheme.metricFont)
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}
