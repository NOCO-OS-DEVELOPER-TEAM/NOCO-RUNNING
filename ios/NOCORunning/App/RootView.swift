import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var summaryRun: Run?
    @State private var selectedTab: AppTab = .home

    private var hideTabs: Bool {
        env.wantsFullscreenRun
            || env.tracker.snapshot.phase != .idle
            || summaryRun != nil
    }

    var body: some View {
        ZStack {
            AmbientField(
                intensity: env.tracker.snapshot.phase == .running || env.tracker.snapshot.phase == .paused ? 0.28 : 1,
                animated: env.tracker.snapshot.phase == .idle
            )
            Group {
                if env.tracker.snapshot.phase == .running
                    || env.tracker.snapshot.phase == .paused
                    || env.tracker.snapshot.phase == .finishing {
                    LiveRunView(onFinished: { run in
                        summaryRun = run
                        env.wantsFullscreenRun = false
                    })
                } else if env.wantsFullscreenRun || env.tracker.snapshot.phase == .preparing {
                    RunPrepView(fullscreen: true)
                } else if let summaryRun {
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
            guard phase == .active else { return }
            Task { await env.syncEverything(context: modelContext) }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .run {
                env.beginRunFlow()
                selectedTab = .home
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onStart: { env.beginRunFlow() })
                .tabItem { Label("Start", systemImage: "sparkles") }
                .tag(AppTab.home)
            Color.clear
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
        .toolbar(hideTabs ? .hidden : .visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

enum AppTab: Hashable {
    case home, run, stats, coach, more
}
