import SwiftUI
import SwiftData

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Training") {
                    NavigationLink("Strecken") { RoutesView() }
                    NavigationLink("Ziele") { GoalsView() }
                    NavigationLink("Rekorde") { RecordsView() }
                    NavigationLink("Gewicht") { WeightView() }
                    NavigationLink("Import") { ImportView() }
                }
                Section("System") {
                    NavigationLink("Einstellungen") { SettingsView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Mehr")
        }
    }
}
