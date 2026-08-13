import SwiftUI

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var intensity: Double = 1
    var bloom: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .padding(16)
            .background { liquid.clipShape(shape) }
            .overlay {
                RainbowBloom(
                    lineWidth: bloom ? 1.6 : 1.15,
                    cornerRadius: cornerRadius,
                    spinning: bloom
                )
            }
            .overlay(alignment: .top) {
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22 * intensity), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.38), radius: bloom ? 22 : 16, y: 10)
            .shadow(color: NocoTheme.violet.opacity(bloom ? 0.18 : 0.08), radius: bloom ? 18 : 8, y: 6)
            .rainbowGlow(radius: bloom ? 20 : 10, opacity: bloom ? 0.55 : 0.22)
    }

    @ViewBuilder
    private var liquid: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        fallbackGlass(shape)
    }

    private func fallbackGlass(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(0.07 * intensity)))
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            NocoTheme.aqua.opacity(0.08 * intensity),
                            NocoTheme.violet.opacity(0.07 * intensity),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
            }
    }
}

struct RainbowGlow: ViewModifier {
    var radius: CGFloat = 18
    var opacity: Double = 0.55

    func body(content: Content) -> some View {
        content
            .shadow(color: NocoTheme.aqua.opacity(opacity * 0.5), radius: radius, y: 0)
            .shadow(color: NocoTheme.violet.opacity(opacity * 0.32), radius: radius + 7, y: 4)
            .shadow(color: NocoTheme.coral.opacity(opacity * 0.22), radius: radius + 12, y: 8)
    }
}

extension View {
    func rainbowGlow(radius: CGFloat = 18, opacity: Double = 0.55) -> some View {
        modifier(RainbowGlow(radius: radius, opacity: opacity))
    }
}

struct AuroraButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(NocoTheme.ink)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NocoTheme.aurora)
            }
            .overlay {
                RainbowBloom(lineWidth: 1.4, cornerRadius: 22, spinning: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .rainbowGlow(radius: 16, opacity: 0.7)
            .intelligenceShimmer()
        }
        .buttonStyle(.plain)
    }
}
