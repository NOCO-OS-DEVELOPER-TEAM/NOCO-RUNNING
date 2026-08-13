import SwiftUI
import SwiftData
import MapKit

struct LiveRunView: View {
    var onFinished: (Run) -> Void
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmStop = false

    private var snap: LiveSnapshot { env.tracker.snapshot }
    private var units: UnitSystem { env.units }
    private var paceEmphasis: Double {
        guard let pace = snap.currentPaceSecondsPerKm else { return 1 }
        return pace < 330 ? 1.08 : 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            VStack {
        topHUD
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .rainbowGlow(radius: 12, opacity: 0.3)
                Spacer()
                bottomHUD
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .confirmationDialog("Lauf beenden?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Lauf speichern", role: .destructive) {
                if let run = env.finishRun(context: modelContext) {
                    onFinished(run)
                }
            }
            Button("Verwerfen", role: .destructive) {
                env.tracker.discardActive()
                env.wantsFullscreenRun = false
            }
            Button("Weiterlaufen", role: .cancel) {}
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if env.tracker.path.count >= 2 {
                MapPolyline(coordinates: env.tracker.path)
                    .stroke(NocoTheme.aqua.opacity(0.9), lineWidth: 5)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            camera = .userLocation(followsHeading: true, fallback: .automatic)
        }
        .onChange(of: snap.phase) { _, phase in
            if phase == .running || phase == .paused {
                camera = .userLocation(followsHeading: true, fallback: .automatic)
            }
        }
    }

    private var topHUD: some View {
        GlassSurface(cornerRadius: 26, intensity: 0.9, bloom: true) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PACE")
                        .font(NocoTheme.captionFont)
                        .foregroundStyle(NocoTheme.mist)
                    Text(RunFormatters.paceClock(snap.currentPaceSecondsPerKm ?? snap.averagePaceSecondsPerKm ?? 0))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .scaleEffect(paceEmphasis)
                        .foregroundStyle(NocoTheme.paceTint(secondsPerKm: snap.currentPaceSecondsPerKm))
                        .animation(NocoMotion.soft, value: paceEmphasis)
                }
                Spacer()
                SpeedGauge(speedMPS: snap.currentSpeedMPS, paceSecondsPerKm: snap.currentPaceSecondsPerKm, units: units)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ZEIT")
                        .font(NocoTheme.captionFont)
                        .foregroundStyle(NocoTheme.mist)
                    Text(RunFormatters.duration(snap.elapsed))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    private var bottomHUD: some View {
        VStack(spacing: 12) {
            MusicChip()
            GlassSurface(cornerRadius: 28) {
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(RunFormatters.distance(snap.distanceMeters, units: units))
                            .font(NocoTheme.heroFont)
                            .monospacedDigit()
                        Text(units.distanceLabel)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(NocoTheme.mist)
                        Spacer()
                        if let hr = snap.heartRate {
                            Label(RunFormatters.heartRate(hr), systemImage: "heart.fill")
                                .foregroundStyle(NocoTheme.coral)
                        }
                    }
                    HStack(spacing: 12) {
                        Button {
                            if snap.phase == .paused {
                                env.tracker.resume()
                            } else {
                                env.tracker.pause()
                            }
                        } label: {
                            Label(snap.phase == .paused ? "Weiter" : "Pause", systemImage: snap.phase == .paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        Button {
                            confirmStop = true
                            Haptics.warning()
                        } label: {
                            Label("Beenden", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(NocoTheme.coral.opacity(0.85))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
