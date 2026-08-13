import Foundation
import SwiftData
import CoreLocation

@MainActor
final class HealthRunSync: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastImportedCount = 0
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var statusText = "Watch-Läufe werden übernommen, sobald Apple Health sie synchronisiert."

    func sync(using health: HealthKitService, context: ModelContext) async -> [Run] {
        guard !isSyncing else { return [] }
        isSyncing = true
        defer { isSyncing = false }

        let drafts = await health.runningWorkoutDrafts(limit: 400)
        let existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        var imported: [Run] = []

        for draft in drafts {
            guard draft.distanceMeters >= 200, draft.duration >= 60 else { continue }
            if alreadyStored(draft, in: existing + imported) { continue }
            let run = makeRun(from: draft)
            context.insert(run)
            imported.append(run)
            _ = RecordDetector.evaluate(run: run, context: context)
        }

        if !imported.isEmpty {
            try? context.save()
        }
        lastImportedCount = imported.count
        lastSyncAt = .now
        if imported.isEmpty {
            statusText = drafts.isEmpty
                ? "Noch keine externen Läufe in Apple Health gefunden."
                : "Alle Watch-Läufe sind bereits in NOCO."
        } else {
            statusText = imported.count == 1
                ? "1 Lauf aus Apple Health / Adidas übernommen."
                : "\(imported.count) Läufe aus Apple Health / Adidas übernommen."
        }
        return imported
    }

    private func alreadyStored(_ draft: HealthWorkoutDraft, in runs: [Run]) -> Bool {
        if runs.contains(where: { $0.healthKitUUID == draft.uuid }) {
            return true
        }
        return runs.contains { run in
            guard run.status == .completed else { return false }
            let startDelta = abs(run.startedAt.timeIntervalSince(draft.startedAt))
            let distanceDelta = abs(run.distanceMeters - draft.distanceMeters)
            return startDelta < 180 && distanceDelta < max(150, draft.distanceMeters * 0.12)
        }
    }

    private func makeRun(from draft: HealthWorkoutDraft) -> Run {
        let run = Run(startedAt: draft.startedAt, status: .completed, source: .appleHealth)
        run.healthKitUUID = draft.uuid
        run.endedAt = draft.endedAt
        run.distanceMeters = draft.distanceMeters
        run.durationSeconds = draft.duration
        run.movingDurationSeconds = draft.duration
        run.calories = draft.calories
        run.elevationGainMeters = draft.elevationGainMeters
        run.averageHeartRate = draft.averageHeartRate
        run.notes = draft.sourceName
        run.routeName = draft.sourceName.contains("adidas") || draft.bundleID.lowercased().contains("adidas")
            ? "adidas Running"
            : draft.sourceName
        run.analysisPending = true

        let samples = downsample(draft.locations)
        for location in samples {
            let point = TrackPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speedMPS: max(0, location.speed),
                accuracy: location.horizontalAccuracy
            )
            point.run = run
            run.points.append(point)
        }
        run.splits = []
        for split in splits(from: draft.locations) {
            split.run = run
            run.splits.append(split)
        }
        return run
    }

    private func downsample(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count > 2500 else { return locations }
        let step = max(1, locations.count / 2000)
        return locations.enumerated().compactMap { offset, location in
            offset.isMultiple(of: step) || offset == locations.count - 1 ? location : nil
        }
    }

    private func splits(from locations: [CLLocation]) -> [Split] {
        guard locations.count >= 2 else { return [] }
        var result: [Split] = []
        var kmIndex = 1
        var travelled = 0.0
        var cursor = locations[0]
        var elevationCursor = locations[0].altitude
        for location in locations.dropFirst() {
            travelled += location.distance(from: cursor)
            cursor = location
            if travelled >= Double(kmIndex) * 1000 {
                let duration = location.timestamp.timeIntervalSince(locations[0].timestamp) - result.reduce(0) { $0 + $1.durationSeconds }
                let elevation = max(0, location.altitude - elevationCursor)
                result.append(
                    Split(
                        kilometerIndex: kmIndex,
                        durationSeconds: max(duration, 1),
                        paceSecondsPerKm: max(duration, 1),
                        elevationDelta: elevation
                    )
                )
                elevationCursor = location.altitude
                kmIndex += 1
            }
        }
        return result
    }
}
