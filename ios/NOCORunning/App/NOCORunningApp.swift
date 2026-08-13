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
                .onOpenURL { url in
                    Task {
                        if let payload = PairingPayload.parse(url.absoluteString) {
                            _ = await environment.ai.pair(with: payload)
                            await environment.syncEverything(context: container.mainContext)
                        }
                    }
                }
        }
        .modelContainer(container)
    }
}
