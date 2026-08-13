import SwiftUI
import SwiftData

struct CoachView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Assistent") { AssistantChatView() }
                    NavigationLink("Fragenportal") { QuestionsPortalView() }
                    NavigationLink("Wochenüberblick") { WeeklyInsightView() }
                    NavigationLink("NOCO AI koppeln") { AIConnectionView() }
                }
                Section("Verbindung") {
                    HStack {
                        Text("Lokale KI")
                        Spacer()
                        AIStatusDot(status: env.ai.reachability)
                    }
                    Text(env.coachSync.statusText)
                        .font(.footnote)
                        .foregroundStyle(NocoTheme.mist)
                    if let synced = env.coachSync.lastSyncAt {
                        Text("Zuletzt synchronisiert: \(synced.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(NocoTheme.mist)
                    }
                    if let err = env.ai.lastError, !err.isEmpty, env.ai.reachability != .connected {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(NocoTheme.coral)
                    }
                    Button("Jetzt synchronisieren") {
                        Task { await env.syncEverything(context: modelContext) }
                    }
                    Button("Verbindung prüfen") {
                        Task { await env.ai.testConnection() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Coach")
            .task {
                await env.ai.testConnection()
            }
        }
    }
}

struct AssistantChatView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @Query private var goals: [Goal]
    @State private var draft = ""
    @State private var busy = false
    @State private var remoteQuestions: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            connectionBanner
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages, id: \.id) { message in
                        HStack {
                            if message.isUser { Spacer(minLength: 40) }
                            Text(message.text)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(message.isUser ? NocoTheme.violet.opacity(0.35) : Color.white.opacity(0.08))
                                )
                                .overlay {
                                    if !message.isUser {
                                        RainbowBloom(lineWidth: 1, cornerRadius: 16, spinning: false)
                                    }
                                }
                            if !message.isUser { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(16)
            }
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button(prompt) { draft = prompt }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                HStack {
                    TextField("Frag deinen Coach…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Senden") { Task { await send() } }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
                .padding(12)
            }
            .background(.ultraThinMaterial)
        }
        .background(Color.clear)
        .navigationTitle("Assistent")
        .task {
            await env.ai.testConnection()
            remoteQuestions = await env.ai.fetchRemoteQuestions()
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        HStack(spacing: 8) {
            AIStatusDot(status: env.ai.reachability)
            Text(bannerText)
                .font(.caption)
                .foregroundStyle(NocoTheme.mist)
            Spacer()
            if env.ai.reachability != .connected {
                Button("Reconnect") {
                    Task {
                        await env.ai.testConnection()
                        remoteQuestions = await env.ai.fetchRemoteQuestions()
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private var bannerText: String {
        switch env.ai.reachability {
        case .connected: return "PC verbunden — Fragen gehen an NOCO AI"
        case .unreachable: return "PC offline — du kannst trotzdem tippen (lokaler Fallback)"
        case .unpaired: return "Noch nicht gekoppelt — QR unter Coach → koppeln"
        case .unknown: return "Verbindung wird geprüft…"
        }
    }

    private var quickPrompts: [String] {
        Array(PersonalizedQuestions.make(
            from: runs,
            weekMeters: StatsMath.distance(runs, from: StatsMath.weekStart()),
            remote: remoteQuestions
        ).prefix(4))
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        modelContext.insert(ChatMessage(isUser: true, text: text))
        try? modelContext.save()
        busy = true
        await env.ai.testConnection()
        let context = StatsMath.athleteContext(
            name: env.athleteName,
            weightKg: env.currentWeight(context: modelContext),
            runs: StatsMath.completedRuns(runs),
            goals: goals
        )
        let reply = await env.ai.chat(question: text, context: context, runID: runs.first?.id)
        let body = [reply.insight, reply.recommendation].compactMap { $0 }.joined(separator: "\n")
        let suffix = reply.source.contains("offline") ? "\n\n(Offline-Coach)" : "\n\n(NOCO AI)"
        modelContext.insert(ChatMessage(isUser: false, text: body + suffix))
        try? modelContext.save()
        busy = false
    }
}

struct QuestionsPortalView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @Query private var goals: [Goal]
    @State private var answer: CoachReply?
    @State private var busy = false
    @State private var remoteQuestions: [String] = []
    @State private var lastRefreshed: Date?

    private var questions: [String] {
        PersonalizedQuestions.make(
            from: runs,
            weekMeters: StatsMath.distance(runs, from: StatsMath.weekStart()),
            remote: remoteQuestions
        )
    }

    var body: some View {
        List {
            Section {
                if let lastRefreshed {
                    Text("Aktualisiert \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
                if let synced = env.coachSync.lastSyncAt {
                    Text("PC-Sync \(synced.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
            }
            Section("Aus deinen Läufen + PC") {
                ForEach(questions, id: \.self) { question in
                    Button(question) {
                        Task { await ask(question) }
                    }
                }
            }
            if !InsightEngine.selfProbes(from: runs).isEmpty {
                Section("Selbstfragen der KI (aus Werten)") {
                    ForEach(InsightEngine.selfProbes(from: runs)) { probe in
                        Button {
                            Task { await askSelf(probe) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(probe.question).font(.body)
                                Text(probe.hypothesis)
                                    .font(.caption)
                                    .foregroundStyle(NocoTheme.mist)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            if busy {
                ProgressView(env.ai.reachability == .connected ? "NOCO AI denkt nach…" : "Offline-Coach…")
            }
            if let answer {
                Section(answer.title) {
                    Text(answer.insight)
                    if let rec = answer.recommendation {
                        Text(rec).foregroundStyle(NocoTheme.mist)
                    }
                    Text(answer.source.contains("offline") ? "Lokaler Coach" : "NOCO AI auf dem PC")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Fragen")
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        await env.ai.testConnection()
        await env.coachSync.syncAll(ai: env.ai, context: modelContext)
        remoteQuestions = await env.ai.fetchRemoteQuestions()
        lastRefreshed = .now
    }

    private func ask(_ question: String) async {
        busy = true
        let context = StatsMath.athleteContext(
            name: env.athleteName,
            weightKg: env.currentWeight(context: modelContext),
            runs: StatsMath.completedRuns(runs),
            goals: goals
        )
        answer = await env.ai.chat(question: question, context: context, runID: runs.first?.id)
        busy = false
    }

    private func askSelf(_ probe: InsightEngine.SelfProbe) async {
        let context = StatsMath.athleteContext(
            name: env.athleteName,
            weightKg: env.currentWeight(context: modelContext),
            runs: StatsMath.completedRuns(runs),
            goals: goals
        )
        let blurb = "Woche \(String(format: "%.1f", context.weekDistanceMeters / 1000)) km, \(context.runCount) Läufe."
        await ask(InsightEngine.pcPrompt(for: probe, contextBlurb: blurb))
    }
}

struct WeeklyInsightView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @Query private var goals: [Goal]
    @State private var pcEnrichment: String?
    @State private var busy = false

    private var overview: String {
        InsightEngine.weeklyOverview(from: runs)
    }

    var body: some View {
        List {
            Section("Diese Woche") {
                Text(overview)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Section("Läufe (ein Satz)") {
                ForEach(StatsMath.completedRuns(runs).filter { $0.startedAt >= StatsMath.weekStart() }, id: \.id) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(RunFormatters.relativeDate(run.startedAt))
                            .font(.caption)
                            .foregroundStyle(NocoTheme.mist)
                        Text(InsightEngine.oneSentence(
                            for: run,
                            typicalPace: StatsMath.typicalPace(from: runs),
                            typicalDistance: StatsMath.typicalDistance(from: runs)
                        ))
                        if let body = run.analysisBody, !body.isEmpty {
                            Text(body)
                                .font(.caption)
                                .foregroundStyle(NocoTheme.mist)
                                .lineLimit(3)
                        }
                    }
                }
            }
            if let pcEnrichment {
                Section("NOCO AI") {
                    Text(pcEnrichment)
                }
            }
            Section {
                Button(busy ? "Fragt PC…" : "Wochenfazit vom PC holen") {
                    Task { await askPC() }
                }
                .disabled(busy)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Woche")
    }

    private func askPC() async {
        busy = true
        let context = StatsMath.athleteContext(
            name: env.athleteName,
            weightKg: env.currentWeight(context: modelContext),
            runs: StatsMath.completedRuns(runs),
            goals: goals
        )
        let prompt = """
        Hier ist mein lokaler Wochenüberblick. Verfeinere ihn in 5–8 Sätzen, stelle eine Selbstfrage zu Tempo/Volumen und beantworte sie nur mit meinen Werten:

        \(overview)
        """
        let reply = await env.ai.chat(question: prompt, context: context)
        pcEnrichment = reply.insight
        busy = false
    }
}
