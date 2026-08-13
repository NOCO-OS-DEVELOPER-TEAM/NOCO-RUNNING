import SwiftUI

struct AmbientField: View {
    var intensity: Double = 1
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion || !animated ? 120 : 1 / 24)) { timeline in
            let t = animated && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                NocoTheme.ink
                RadialGradient(
                    colors: [
                        NocoTheme.violet.opacity(0.22 * intensity),
                        NocoTheme.ink.opacity(0)
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 420
                )
                orb(color: NocoTheme.aqua, x: 0.18 + 0.04 * cos(t / 7), y: 0.22 + 0.05 * sin(t / 6), size: 280)
                orb(color: NocoTheme.violet, x: 0.86 + 0.03 * sin(t / 8), y: 0.18 + 0.04 * cos(t / 5), size: 240)
                orb(color: NocoTheme.coral, x: 0.72 + 0.05 * cos(t / 9), y: 0.78 + 0.03 * sin(t / 7), size: 260)
                orb(color: NocoTheme.sun, x: 0.28 + 0.04 * sin(t / 10), y: 0.84 + 0.03 * cos(t / 8), size: 180)
                LinearGradient(
                    colors: [Color.white.opacity(0.05 * intensity), .clear, NocoTheme.aqua.opacity(0.06 * intensity)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func orb(color: Color, x: Double, y: Double, size: CGFloat) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(color.opacity(0.38 * intensity))
                .frame(width: size, height: size)
                .blur(radius: 48)
                .position(x: geo.size.width * x, y: geo.size.height * y)
        }
    }
}

struct RainbowBloom: View {
    var lineWidth: CGFloat = 1.4
    var cornerRadius: CGFloat = 24
    var spinning: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion || !spinning ? 120 : 1 / 20)) { timeline in
            let turn = spinning && !reduceMotion
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9) / 9
                : 0.12
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            NocoTheme.aqua,
                            NocoTheme.violet,
                            NocoTheme.coral,
                            NocoTheme.sun,
                            NocoTheme.aqua
                        ],
                        center: .center,
                        angle: .degrees(turn * 360)
                    ),
                    lineWidth: lineWidth
                )
                .opacity(0.85)
                .blur(radius: 0.2)
        }
        .allowsHitTesting(false)
    }
}

struct IntelligenceShimmer: ViewModifier {
    var active: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.18),
                            NocoTheme.aqua.opacity(0.16),
                            Color.white.opacity(0.1),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: (phase - 0.5) * 220)
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            }
        }
    }
}

struct IntelligenceSparkle: View {
    var body: some View {
        Image(systemName: "sparkles")
            .symbolRenderingMode(.palette)
            .foregroundStyle(NocoTheme.aurora)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .symbolEffect(.pulse, options: .repeating)
    }
}

extension View {
    func intelligenceShimmer(_ active: Bool = true) -> some View {
        modifier(IntelligenceShimmer(active: active))
    }
}
