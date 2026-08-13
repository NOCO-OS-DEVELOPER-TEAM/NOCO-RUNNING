import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var summaryRun: Run?
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack {
            AmbientField(intensity: env.tracker.snapshot.phase == .running || env.tracker.snapshot.phase == .paused ? 0.35 : 1)
            switch env.tracker.snapshot.phase {
            case .preparing:
                RunPrepView()
            case .running, .paused, .finishing:
                LiveRunView(onFinished: { run in
                    summaryRun = run
                })
            default:
                if let summaryRun {
                    RunSummaryView(run: summaryRun) {
                        self.summaryRun = nil
                    }
                } else {
                    tabShell
                }
            }
        }
        .tint(NocoTheme.aqua)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, env.tracker.snapshot.phase == .idle else { return }
            Task { await env.syncHealthRuns(context: modelContext) }
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onStart: { env.tracker.prepareGPS() })
                .tabItem { Label("Start", systemImage: "sparkles") }
                .tag(AppTab.home)
            RunPrepView()
                .tabItem { Label("Laufen", systemImage: "figure.run") }
                .tag(AppTab.run)
            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.stats)
            CoachView()
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
                .tag(AppTab.coach)
            MoreView()
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

enum AppTab: Hashable {
    case home, run, stats, coach, more
}
