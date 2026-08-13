import SwiftUI

struct MusicChip: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        GlassSurface(cornerRadius: 18, intensity: 0.8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(env.music.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(env.music.artist)
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: env.music.previous) {
                    Image(systemName: "backward.fill")
                }
                Button(action: env.music.toggle) {
                    Image(systemName: env.music.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: env.music.next) {
                    Image(systemName: "forward.fill")
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
    }
}
