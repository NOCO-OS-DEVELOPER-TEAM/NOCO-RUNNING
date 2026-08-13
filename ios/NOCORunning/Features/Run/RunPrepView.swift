import SwiftUI
import SwiftData

struct RunPrepView: View {
    var fullscreen: Bool = false
    @EnvironmentObject private var env: AppEnvironment
    @Query(sort: \SavedRoute.lastUsedAt, order: .reverse) private var routes: [SavedRoute]
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var selectedRoute: SavedRoute?
    @State private var hint: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if fullscreen {
                    HStack {
                        Button("Abbrechen") {
                            env.cancelRunFlow()
                        }
                        Spacer()
                        IntelligenceSparkle()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Spacer()
                GlassSurface(cornerRadius: 28, bloom: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Vorbereitung")
                            .font(.headline)
                        PrepRow(title: "GPS", ready: env.tracker.snapshot.gpsReady, detail: accuracyText)
                        PrepRow(title: "Health", ready: env.health.isAuthorized || !env.health.isAvailable, detail: env.health.isAvailable ? (env.health.isAuthorized ? "Verbunden" : "Optional") : "Nicht verfügbar")
                        PrepRow(title: "Musik", ready: true, detail: env.music.title)
                        PrepRow(
                            title: "NOCO AI",
                            ready: env.ai.reachability == .connected || env.ai.reachability == .unpaired || env.ai.reachability == .unknown,
                            detail: coachDetail
                        )
                    }
                }
                .padding(.horizontal, 20)

                if let selectedRoute {
                    Text("Strecke: \(selectedRoute.name)")
                        .font(.subheadline)
                        .foregroundStyle(NocoTheme.mist)
                } else if !hint.isEmpty {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(NocoTheme.mist)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .intelligenceShimmer()
                }

                AuroraButton(
                    title: env.tracker.snapshot.gpsReady ? "Jetzt loslaufen" : "Trotzdem starten",
                    systemImage: "figure.run"
                ) {
                    env.tracker.start(routeName: selectedRoute?.name)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .navigationBarHidden(fullscreen)
            .navigationTitle("Lauf")
            .toolbar {
                if !fullscreen {
                    ToolbarItem(placement: .topBarTrailing) {
                        routeMenu
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if fullscreen {
                    routeMenu
                        .padding(.horizontal, 20)
                }
            }
            .onAppear {
                env.tracker.prepareGPS()
                Task {
                    let context = StatsMath.athleteContext(
                        name: env.athleteName,
                        weightKg: nil,
                        runs: StatsMath.completedRuns(runs),
                        goals: []
                    )
                    hint = await env.ai.recommendRoute(context: context)
                }
            }
        }
    }

    private var routeMenu: some View {
        Menu("Strecke") {
            Button("Freies Laufen") { selectedRoute = nil }
            ForEach(routes.prefix(8), id: \.id) { route in
                Button(route.name) { selectedRoute = route }
            }
        }
    }

    private var coachDetail: String {
        switch env.ai.reachability {
        case .connected: return "PC verbunden"
        case .unpaired: return "QR koppeln"
        case .unreachable: return "Offline-Coach"
        case .unknown: return "Prüfe…"
        }
    }

    private var accuracyText: String {
        if let accuracy = env.tracker.snapshot.gpsAccuracy, accuracy > 0 {
            return String(format: "±%.0f m", accuracy)
        }
        return "Suche Standort"
    }
}

private struct PrepRow: View {
    var title: String
    var ready: Bool
    var detail: String

    var body: some View {
        HStack {
            Circle()
                .fill(ready ? NocoTheme.aqua : NocoTheme.sun)
                .frame(width: 9, height: 9)
                .rainbowGlow(radius: 4, opacity: ready ? 0.5 : 0.2)
            Text(title).font(.headline)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(NocoTheme.mist)
        }
    }
}
