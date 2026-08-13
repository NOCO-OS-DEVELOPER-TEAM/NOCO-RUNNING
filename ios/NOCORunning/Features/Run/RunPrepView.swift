import SwiftUI
import SwiftData

struct RunPrepView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Query(sort: \SavedRoute.lastUsedAt, order: .reverse) private var routes: [SavedRoute]
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var selectedRoute: SavedRoute?
    @State private var hint: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 14) {
                    PrepRow(title: "GPS", ready: env.tracker.snapshot.gpsReady, detail: accuracyText)
                    PrepRow(title: "Health", ready: env.health.isAuthorized || !env.health.isAvailable, detail: env.health.isAvailable ? (env.health.isAuthorized ? "Verbunden" : "Optional") : "Nicht verfügbar")
                    PrepRow(title: "Musik", ready: true, detail: env.music.title)
                    PrepRow(title: "KI-Coach", ready: env.ai.reachability != .unreachable, detail: env.ai.reachability == .connected ? "Verbunden" : "Offline-Coach aktiv")
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
                }

                Button {
                    env.tracker.start(routeName: selectedRoute?.name)
                } label: {
                    Text(env.tracker.snapshot.gpsReady ? "Jetzt loslaufen" : "Trotzdem starten")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(NocoTheme.aurora)
                        .foregroundStyle(NocoTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(NocoTheme.ink.ignoresSafeArea())
            .navigationTitle("Lauf")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Strecke") {
                        Button("Freies Laufen") { selectedRoute = nil }
                        ForEach(routes.prefix(8), id: \.id) { route in
                            Button(route.name) { selectedRoute = route }
                        }
                    }
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
        GlassSurface(cornerRadius: 18) {
            HStack {
                Circle()
                    .fill(ready ? NocoTheme.aqua : NocoTheme.sun)
                    .frame(width: 9, height: 9)
                Text(title).font(.headline)
                Spacer()
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(NocoTheme.mist)
            }
        }
    }
}
