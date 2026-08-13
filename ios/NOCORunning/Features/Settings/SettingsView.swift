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
                NavigationLink("NOCO AI / QR") { AIConnectionView() }
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
            Section("Apple Watch / Adidas Running") {
                Text("Joggen nur mit der Watch oder mit adidas Running geht. Die Trainings landen in Apple Health. NOCO übernimmt Distanz, Zeit, Pace, Puls und wenn möglich die Strecke — auch alte Läufe.")
                    .font(.footnote)
                    .foregroundStyle(NocoTheme.mist)
                Text(env.healthSync.statusText)
                    .font(.subheadline)
                if let synced = env.healthSync.lastSyncAt {
                    Text("Zuletzt geprüft: \(synced.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
                Button("Alle Health-/Adidas-Läufe übernehmen") {
                    Task { await env.syncEverything(context: modelContext) }
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
    @Environment(\.modelContext) private var modelContext
    @State private var showScanner = false
    @State private var manualHost = ""
    @State private var manualPin = ""
    @State private var port = 4747
    @State private var pairing = false
    @State private var message = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        IntelligenceSparkle()
                        Text("NOCO AI Plugin")
                            .font(.headline)
                    }
                    Text("Scanne den QR-Code aus dem NOCO-RUNNING-Plugin auf dem Windows-PC. Danach synchronisieren Läufe, Analysen und Fragen automatisch.")
                        .font(.footnote)
                        .foregroundStyle(NocoTheme.mist)
                    AIStatusDot(status: env.ai.reachability)
                    if env.ai.configuration.isPaired {
                        Text("\(env.ai.configuration.host):\(env.ai.configuration.port)")
                            .font(.caption.monospaced())
                            .foregroundStyle(NocoTheme.mist)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Koppeln") {
                Button {
                    showScanner = true
                } label: {
                    Label("QR-Code scannen", systemImage: "qrcode.viewfinder")
                }
                .disabled(pairing)

                Button("Jetzt synchronisieren") {
                    Task { await env.syncEverything(context: modelContext) }
                }
                .disabled(!env.ai.configuration.isPaired)

                if env.ai.configuration.isPaired {
                    Button("Entkoppeln", role: .destructive) {
                        env.ai.unpair()
                        message = "Entkoppelt."
                    }
                }
            }

            Section("Fallback ohne QR") {
                TextField("PC-IP", text: $manualHost)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("PIN", text: $manualPin)
                    .keyboardType(.numberPad)
                Stepper("Port \(port)", value: $port, in: 1...65535)
                Button("Mit PIN koppeln") {
                    Task { await pairManual() }
                }
                .disabled(manualHost.isEmpty || manualPin.isEmpty || pairing)
            }

            Section("Status") {
                Text(env.coachSync.statusText)
                if let checked = env.ai.lastCheckedAt {
                    Text("Zuletzt geprüft: \(checked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
                if let err = env.ai.lastError, !err.isEmpty {
                    Text(err).foregroundStyle(NocoTheme.coral)
                }
                if !message.isEmpty {
                    Text(message).foregroundStyle(NocoTheme.aqua)
                }
                Text("Firewall: TCP 4747 im privaten Netz erlauben. Tracking funktioniert immer auch offline.")
                    .font(.footnote)
                    .foregroundStyle(NocoTheme.mist)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("NOCO AI")
        .sheet(isPresented: $showScanner) {
            QRPairingScannerView { code in
                Task { await pair(code: code) }
            }
        }
        .onAppear {
            manualHost = env.ai.configuration.host
            port = env.ai.configuration.port == 0 ? 4747 : env.ai.configuration.port
        }
    }

    private func pair(code: String) async {
        guard let payload = PairingPayload.parse(code) else {
            message = "QR nicht erkannt. Bitte den Code aus NOCO AI scannen."
            return
        }
        pairing = true
        let ok = await env.ai.pair(with: payload)
        pairing = false
        message = ok ? "Gekoppelt. Sync startet…" : (env.ai.lastError ?? "Pairing fehlgeschlagen")
        if ok {
            await env.syncEverything(context: modelContext)
            Haptics.record()
        }
    }

    private func pairManual() async {
        let payload = PairingPayload(host: manualHost, port: port, pin: manualPin, lanHost: manualHost, remoteHost: nil)
        pairing = true
        let ok = await env.ai.pair(with: payload)
        pairing = false
        message = ok ? "Gekoppelt." : (env.ai.lastError ?? "Pairing fehlgeschlagen")
        if ok { await env.syncEverything(context: modelContext) }
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
