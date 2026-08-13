import SwiftUI

struct SpeedGauge: View {
    var speedMPS: Double
    var paceSecondsPerKm: Double?
    var units: UnitSystem

    private var kmh: Double { max(0, speedMPS * 3.6) }
    private var progress: Double { min(kmh / 20, 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * progress)
                .stroke(
                    AngularGradient(
                        colors: [NocoTheme.aqua, NocoTheme.violet, NocoTheme.coral, NocoTheme.aqua],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .rainbowGlow(radius: 8, opacity: 0.35 + progress * 0.4)
                .animation(.easeOut(duration: 0.45), value: progress)

            VStack(spacing: 2) {
                Text(RunFormatters.speed(metersPerSecond: speedMPS, units: units))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: kmh))
                Text(units.speedLabel)
                    .font(NocoTheme.captionFont)
                    .foregroundStyle(NocoTheme.mist)
                Text(RunFormatters.pace(secondsPerKm: paceSecondsPerKm, units: units))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(NocoTheme.paceTint(secondsPerKm: paceSecondsPerKm))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Geschwindigkeit \(RunFormatters.speed(metersPerSecond: speedMPS, units: units)) \(units.speedLabel)")
    }
}

struct ProgressRing: View {
    var progress: Double
    var label: String
    var detail: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(NocoTheme.aurora, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(NocoMotion.soft, value: progress)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.headline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NocoTheme.mist)
            }
            Spacer()
        }
    }
}
