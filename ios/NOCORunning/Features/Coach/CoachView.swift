import SwiftUI
import SwiftData

struct CoachView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Assistent") { AssistantChatView() }
                    NavigationLink("Fragenportal") { QuestionsPortalView() }
                }
                Section("Verbindung") {
                    HStack {
                        Text("Lokale KI")
                        Spacer()
                        AIStatusDot(status: env.ai.reachability)
                    }
                    Text("Tracking läuft immer lokal. Der Coach holt Analysen nach, sobald dein PC erreichbar ist.")
                        .font(.footnote)
                        .foregroundStyle(NocoTheme.mist)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NocoTheme.ink.ignoresSafeArea())
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
                                .background(message.isUser ? NocoTheme.violet.opacity(0.35) : Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            if !message.isUser { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(16)
            }
            HStack {
                TextField("Frag deinen Coach…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Senden") { Task { await send() } }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            .padding(12)
        }
        .background(NocoTheme.ink.ignoresSafeArea())
        .navigationTitle("Assistent")
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
        let reply = await env.ai.chat(question: text, context: context)
        let body = [reply.insight, reply.recommendation].compactMap { $0 }.joined(separator: "\n")
        modelContext.insert(ChatMessage(isUser: false, text: body))
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

    private let questions = [
        "Wie kann ich schneller werden?",
        "Warum war meine Pace heute schlechter?",
        "Wie oft sollte ich laufen?",
        "Wie lange sollte ein lockerer Lauf sein?",
        "Wie verbessere ich meine Ausdauer?",
        "Was war mein bester Lauf?",
        "Wie hat sich meine Leistung entwickelt?"
    ]

    var body: some View {
        List {
            Section {
                ForEach(questions, id: \.self) { question in
                    Button(question) {
                        Task { await ask(question) }
                    }
                }
            }
            if busy {
                ProgressView("Coach denkt nach…")
            }
            if let answer {
                Section(answer.title) {
                    Text(answer.insight)
                    if let rec = answer.recommendation {
                        Text(rec).foregroundStyle(NocoTheme.mist)
                    }
                    Text(answer.source == "offline" ? "Lokaler Coach" : "PC-KI")
                        .font(.caption)
                        .foregroundStyle(NocoTheme.mist)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
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
        answer = await env.ai.chat(question: question, context: context)
        busy = false
    }
}
