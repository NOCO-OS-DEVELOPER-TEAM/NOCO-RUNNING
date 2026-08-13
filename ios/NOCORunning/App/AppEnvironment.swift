import Foundation
import SwiftData
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let tracker = RunTracker()
    let health = HealthKitService()
    let healthSync = HealthRunSync()
    let coachSync = CoachSyncService()
    let music = MusicController()
    let weather = WeatherService()
    let ai = AIClient()
    let liveActivity = LiveActivityManager()
    let notifications = NotificationService()

    @Published var units: UnitSystem = .metric
    @Published var athleteName: String = ""
    @Published var newRecords: [PersonalRecord] = []
    @Published var wantsFullscreenRun = false

    private var analysisQueue: AnalysisQueue?
    private var cancellables: Set<AnyCancellable> = []

    func bootstrap(context: ModelContext) {
        bind(healthSync)
        bind(coachSync)
        bind(health)
        bind(tracker)
        bind(ai)
        bind(music)
        ensureProfile(context: context)
        let weight = currentWeight(context: context)
        tracker.configure(context: context, health: health, liveActivity: liveActivity, weightKg: weight)
        tracker.restoreIfNeeded()
        if tracker.snapshot.phase != .idle {
            wantsFullscreenRun = true
        }
        analysisQueue = AnalysisQueue(ai: ai)
        Task {
            await health.requestAccess()
            _ = await healthSync.sync(using: health, context: context)
            await ai.testConnection()
            await coachSync.syncAll(ai: ai, context: context)
            let profile = currentProfile(context: context)
            let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
            let athlete = StatsMath.athleteContext(name: profile?.name ?? "", weightKg: weight, runs: runs, goals: goals)
            await analysisQueue?.processPending(context: context, athlete: athlete)
        }
    }

    func beginRunFlow() {
        wantsFullscreenRun = true
        tracker.prepareGPS()
        Haptics.medium()
    }

    func cancelRunFlow() {
        if tracker.snapshot.phase == .preparing || tracker.snapshot.phase == .idle {
            wantsFullscreenRun = false
            tracker.discardActive()
        }
    }

    func finishRun(context: ModelContext) -> Run? {
        guard let run = tracker.finish() else { return nil }
        wantsFullscreenRun = false
        weather.attach(to: run)
        newRecords = RecordDetector.evaluate(run: run, context: context)
        Task { await health.saveCompletedRun(run) }
        Task {
            let weight = currentWeight(context: context)
            let profile = currentProfile(context: context)
            let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
            let athlete = StatsMath.athleteContext(name: profile?.name ?? "", weightKg: weight, runs: runs, goals: goals)
            let reply = await ai.analyze(run: run.toDTO(), context: athlete)
            run.analysisTitle = reply.title
            run.analysisBody = [reply.insight, reply.recommendation].compactMap { $0 }.joined(separator: "\n")
            run.analysisPending = false
            try? context.save()
            await coachSync.syncAll(ai: ai, context: context, force: false)
        }
        return run
    }

    func syncEverything(context: ModelContext) async {
        await health.requestAccess()
        let imported = await healthSync.sync(using: health, context: context)
        await ai.testConnection()
        await coachSync.syncAll(ai: ai, context: context, force: true)
        if !imported.isEmpty {
            let weight = currentWeight(context: context)
            let profile = currentProfile(context: context)
            let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
            let athlete = StatsMath.athleteContext(name: profile?.name ?? "", weightKg: weight, runs: runs, goals: goals)
            await analysisQueue?.processPending(context: context, athlete: athlete)
        }
    }

    func syncHealthRuns(context: ModelContext) async {
        await syncEverything(context: context)
    }

    func currentWeight(context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.kilograms
    }

    func currentProfile(context: ModelContext) -> UserProfile? {
        (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
    }

    private func ensureProfile(context: ModelContext) {
        if let profile = currentProfile(context: context) {
            units = profile.units
            athleteName = profile.name
            return
        }
        let profile = UserProfile()
        context.insert(profile)
        if (try? context.fetch(FetchDescriptor<Goal>()))?.isEmpty != false {
            context.insert(Goal(kind: .weeklyDistance, targetValue: 20_000))
        }
        try? context.save()
    }

    private func bind<T: ObservableObject>(_ child: T) {
        child.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
