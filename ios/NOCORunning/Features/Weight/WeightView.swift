import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date) private var entries: [WeightEntry]
    @State private var kilograms: Double = 72
    @State private var note = ""

    var body: some View {
        Form {
            Section("Aktuell") {
                if let last = entries.last {
                    Text(String(format: "%.1f kg", last.kilograms))
                        .font(NocoTheme.metricFont)
                    if entries.count >= 2 {
                        let delta = last.kilograms - entries[entries.count - 2].kilograms
                        Text(String(format: "%@%.1f kg seit dem letzten Eintrag", delta >= 0 ? "+" : "", delta))
                            .foregroundStyle(delta > 0 ? NocoTheme.coral : NocoTheme.aqua)
                    }
                } else {
                    Text("Noch kein Gewicht hinterlegt")
                }
            }
            Section("Neuer Eintrag") {
                Stepper(value: $kilograms, in: 40...180, step: 0.1) {
                    Text(String(format: "%.1f kg", kilograms))
                }
                TextField("Notiz", text: $note)
                Button("Speichern") {
                    modelContext.insert(WeightEntry(kilograms: kilograms, note: note.isEmpty ? nil : note))
                    try? modelContext.save()
                    note = ""
                    Haptics.medium()
                }
            }
            if entries.count >= 2 {
                Section("Verlauf") {
                    Chart(entries, id: \.date) { entry in
                        LineMark(
                            x: .value("Datum", entry.date),
                            y: .value("kg", entry.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(NocoTheme.aqua)
                    }
                    .frame(height: 180)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Gewicht")
        .onAppear {
            if let last = entries.last { kilograms = last.kilograms }
        }
    }
}
