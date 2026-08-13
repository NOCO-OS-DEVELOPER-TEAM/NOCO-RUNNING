import Foundation
import SwiftData

@MainActor
final class AnalysisQueue {
    private let ai: AIClient

    init(ai: AIClient) {
        self.ai = ai
    }

    func processPending(context: ModelContext, athlete: AthleteContext) async {
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.analysisPending == true && $0.statusRaw == "completed" }
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        for run in pending.prefix(5) {
            let reply = await ai.analyze(run: run.toDTO(), context: athlete)
            run.analysisTitle = reply.title
            run.analysisBody = [reply.insight, reply.recommendation].compactMap { $0 }.joined(separator: "\n")
            run.analysisPending = false
            try? context.save()
        }
    }
}
