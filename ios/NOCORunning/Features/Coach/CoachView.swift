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
                    Button("Jetzt synchronisieren") {
                        Task { await env.syncEverything(context: modelContext) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Coach")
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

    var body: some View {
        VStack(spacing: 0) {
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
    }

    private var quickPrompts: [String] {
        Array(PersonalizedQuestions.make(
            from: runs,
            weekMeters: StatsMath.distance(runs, from: StatsMath.weekStart())
        ).prefix(4))
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        modelContext.insert(ChatMessage(isUser: true, text: text))
        try? modelContext.save()
        busy = true
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

    private var questions: [String] {
        PersonalizedQuestions.make(
            from: runs,
            weekMeters: StatsMath.distance(runs, from: StatsMath.weekStart())
        )
    }

    var body: some View {
        List {
            Section("Aus deinen Läufen") {
                ForEach(questions, id: \.self) { question in
                    Button(question) {
                        Task { await ask(question) }
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
}
