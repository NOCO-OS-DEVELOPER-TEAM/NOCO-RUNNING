import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var env: AppEnvironment
    @State private var text = ""
    @State private var draft: ImportedRunDraft?
    @State private var busy = false
    @State private var importerPresented = false

    var body: some View {
        Form {
            Section("Text einfügen") {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                Button("Erkennen") { Task { await parse() } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            Section("Datei") {
                Button("CSV / Text importieren") { importerPresented = true }
            }
            if let draft {
                Section("Prüfung") {
                    DatePicker(
                        "Datum",
                        selection: Binding(
                            get: { draft.startedAt ?? .now },
                            set: { self.draft?.startedAt = $0 }
                        ),
                        displayedComponents: .date
                    )
                    HStack {
                        Text("Distanz (km)")
                        Spacer()
                        TextField("km", value: Binding(
                            get: { (draft.distanceMeters ?? 0) / 1000 },
                            set: { self.draft?.distanceMeters = $0 * 1000 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Zeit (Minuten)")
                        Spacer()
                        TextField("min", value: Binding(
                            get: { (draft.duration ?? 0) / 60 },
                            set: { self.draft?.duration = $0 * 60 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    Text("Konfidenz \(Int((draft.confidence) * 100)) %")
                        .foregroundStyle(NocoTheme.mist)
                    Button("Lauf speichern") { save(draft) }
                        .disabled(draft.distanceMeters == nil)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Import")
        .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.plainText, .commaSeparatedText]) { result in
            if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                Task { await parse() }
            }
        }
    }

    private func parse() async {
        busy = true
        draft = await env.ai.importText(text)
        busy = false
    }

    private func save(_ draft: ImportedRunDraft) {
        let run = Run(startedAt: draft.startedAt ?? .now, status: .completed, source: .imported)
        run.endedAt = run.startedAt.addingTimeInterval(draft.duration ?? 0)
        run.distanceMeters = draft.distanceMeters ?? 0
        run.durationSeconds = draft.duration ?? 0
        run.movingDurationSeconds = draft.duration ?? 0
        run.averageHeartRate = draft.averageHeartRate
        run.calories = draft.calories
        run.notes = draft.notes
        run.analysisPending = true
        modelContext.insert(run)
        _ = RecordDetector.evaluate(run: run, context: modelContext)
        try? modelContext.save()
        self.draft = nil
        text = ""
        Haptics.medium()
    }
}
