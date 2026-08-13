import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        List {
            Section("Profil") {
                TextField("Name", text: Binding(
                    get: { profile?.name ?? "" },
                    set: {
                        profile?.name = $0
                        env.athleteName = $0
                        try? modelContext.save()
                    }
                ))
                Picker("Einheiten", selection: Binding(
                    get: { profile?.units ?? .metric },
                    set: {
                        profile?.units = $0
                        env.units = $0
                        try? modelContext.save()
                    }
                )) {
                    Text("Kilometer").tag(UnitSystem.metric)
                    Text("Meilen").tag(UnitSystem.imperial)
                }
            }
            Section("Apple") {
                NavigationLink("HealthKit") { HealthSettingsView() }
            }
            Section("KI") {
                NavigationLink("Lokale Verbindung") { AIConnectionView() }
            }
            Section("Daten") {
                NavigationLink("Import / Export / Reset") { DataSettingsView() }
            }
            Section("Darstellung") {
                Toggle("Animationen", isOn: Binding(
                    get: { profile?.animationsEnabled ?? true },
                    set: {
                        profile?.animationsEnabled = $0
                        try? modelContext.save()
                    }
                ))
            }
            Section("Datenschutz") {
                Text("Läufe bleiben auf diesem iPhone. Die KI-API spricht nur deinen eigenen PC im lokalen Netz an — keine Cloud.")
                    .font(.footnote)
                    .foregroundStyle(NocoTheme.mist)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Einstellungen")
    }
}

struct HealthSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("HealthKit") {
                    Text(env.health.isAvailable ? (env.health.isAuthorized ? "Verbunden" : "Berechtigung nötig") : "Nicht verfügbar")
                }
                if let hr = env.health.latestHeartRate {
                    LabeledContent("Puls", value: "\(Int(hr)) bpm")
                }
                if let steps = env.health.latestSteps {
                    LabeledContent("Schritte heute", value: "\(Int(steps))")
                }
                Button("Zugriff anfordern") {
                    Task { await env.health.requestAccess() }
                }
            }
            Section("Apple Watch ohne iPhone") {
                Text("Joggen nur mit der Watch geht. Starte in der Apple-Trainings-App „Laufen im Freien“. Das iPhone kann zu Hause bleiben. Sobald Watch und iPhone sich wieder sehen, liegt der Lauf in Apple Health und NOCO übernimmt Distanz, Zeit, Pace, Puls und wenn möglich die Strecke.")
                    .font(.footnote)
                    .foregroundStyle(NocoTheme.mist)
                Text(env.healthSync.statusText)
                    .font(.subheadline)
                if let synced = env.healthSync.lastSyncAt {
                    Text("Zuletzt geprüft: \(synced.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
                Button("Watch-Läufe jetzt übernehmen") {
                    Task { await env.syncHealthRuns(context: modelContext) }
                }
                .disabled(env.healthSync.isSyncing)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Health")
        .task { await env.health.refreshSnapshot() }
    }
}

struct AIConnectionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var host = ""
    @State private var port = 8787
    @State private var token = ""
    @State private var tls = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("IP oder Hostname", text: $host)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                Stepper("Port \(port)", value: $port, in: 1...65535)
                Toggle("HTTPS", isOn: $tls)
                SecureField("API-Token (optional)", text: $token)
            }
            Section("Status") {
                AIStatusDot(status: env.ai.reachability)
                if let checked = env.ai.lastCheckedAt {
                    Text("Zuletzt geprüft: \(checked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
                Button("Verbindung testen") {
                    persist()
                    Task { await env.ai.testConnection() }
                }
            }
            Section {
                Text("Der PC muss im selben Netz sein. Windows-Firewall: Port \(port) für private Netze zulassen.")
                    .font(.footnote)
                    .foregroundStyle(NocoTheme.mist)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("KI-Verbindung")
        .onAppear {
            let config = env.ai.configuration
            host = config.host
            port = config.port
            token = config.token
            tls = config.useTLS
        }
        .onDisappear { persist() }
    }

    private func persist() {
        var config = env.ai.configuration
        config.host = host
        config.port = port
        config.token = token
        config.useTLS = tls
        config.persist()
        env.ai.configuration = config
    }
}

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ShareLink(item: exportJSON()) {
                    Label("Läufe exportieren", systemImage: "square.and.arrow.up")
                }
                NavigationLink("Daten importieren") { ImportView() }
            }
            Section {
                Button("Alle Laufdaten löschen", role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Daten")
        .confirmationDialog("Wirklich alles löschen?", isPresented: $confirmReset) {
            Button("Löschen", role: .destructive) {
                for run in runs { modelContext.delete(run) }
                try? modelContext.save()
            }
        }
    }

    private func exportJSON() -> String {
        let payload = StatsMath.completedRuns(runs).map { $0.toDTO() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
