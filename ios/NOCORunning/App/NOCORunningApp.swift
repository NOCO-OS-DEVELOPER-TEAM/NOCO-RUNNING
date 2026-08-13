import SwiftUI
import SwiftData

@main
struct NOCORunningApp: App {
    @StateObject private var environment = AppEnvironment()
    private let container = Persistence.container()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(.dark)
                .task {
                    environment.bootstrap(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
