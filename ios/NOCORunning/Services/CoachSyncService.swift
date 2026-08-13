import Foundation
import SwiftData

@MainActor
final class CoachSyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var statusText = "Nach dem QR-Scan synchronisiert NOCO deine Läufe mit dem PC."
    @Published private(set) var lastImported = 0
    @Published private(set) var lastUpdated = 0

    private var lastPushCursor: Date? {
        get { UserDefaults.standard.object(forKey: "noco.sync.lastPush") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "noco.sync.lastPush") }
    }

    func syncAll(ai: AIClient, context: ModelContext, force: Bool = false) async {
        guard ai.configuration.isPaired else {
            statusText = "Noch nicht gekoppelt — QR-Code in NOCO AI scannen."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await ai.testConnection()
        guard ai.reachability == .connected else {
            statusText = "PC offline — Offline-Coach bleibt aktiv. Sync später."
            return
        }

        let runs = StatsMath.completedRuns((try? context.fetch(FetchDescriptor<Run>())) ?? [])
        let pending = force ? runs : runs.filter { run in
            guard let cursor = lastPushCursor else { return true }
            let stamp = run.endedAt ?? run.startedAt
            return stamp >= cursor || run.analysisPending
        }
        guard !pending.isEmpty else {
            statusText = "Alles synchron — \(runs.count) Läufe auf dem Gerät."
            lastSyncAt = .now
            return
        }

        if let result = await ai.pushRuns(pending) {
            lastImported = result.imported ?? 0
            lastUpdated = result.updated ?? 0
            lastPushCursor = .now
            lastSyncAt = .now
            let stamp = lastSyncAt!.formatted(date: .abbreviated, time: .shortened)
            statusText = "Sync ok (\(stamp)): \(lastImported) neu, \(lastUpdated) aktualisiert."
            for run in pending where run.analysisPending {
                let athlete = StatsMath.athleteContext(
                    name: "",
                    weightKg: nil,
                    runs: runs,
                    goals: []
                )
                let reply = await ai.analyze(run: run.toDTO(), context: athlete)
                run.analysisTitle = reply.title
                run.analysisBody = [reply.insight, reply.recommendation].compactMap { $0 }.joined(separator: "\n")
                run.analysisPending = false
            }
            try? context.save()
        } else {
            statusText = "Sync fehlgeschlagen — Offline weiter nutzbar."
        }
    }
}
