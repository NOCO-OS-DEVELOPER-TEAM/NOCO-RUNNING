import SwiftUI

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var intensity: Double = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background { glass }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38 * intensity),
                                Color.white.opacity(0.06 * intensity),
                                NocoTheme.aqua.opacity(0.18 * intensity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
    }

    @ViewBuilder
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        fallbackGlass(shape)
    }

    private func fallbackGlass(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(0.06 * intensity)))
            .overlay(alignment: .top) {
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18 * intensity), .clear],
                            startPoint: .top,
                            endPoint: .center
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
            .shadow(color: NocoTheme.aqua.opacity(opacity * 0.45), radius: radius, y: 0)
            .shadow(color: NocoTheme.violet.opacity(opacity * 0.28), radius: radius + 6, y: 4)
            .shadow(color: NocoTheme.coral.opacity(opacity * 0.18), radius: radius + 10, y: 8)
    }
}

extension View {
    func rainbowGlow(radius: CGFloat = 18, opacity: Double = 0.55) -> some View {
        modifier(RainbowGlow(radius: radius, opacity: opacity))
    }
}
