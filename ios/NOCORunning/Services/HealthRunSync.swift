import Foundation
import SwiftData
import CoreLocation

@MainActor
final class HealthRunSync: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastImportedCount = 0
    @Published private(set) var lastUpdatedCount = 0
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var statusText = "Watch- und Adidas-Läufe landen über Apple Health in NOCO."

    func sync(using health: HealthKitService, context: ModelContext) async -> [Run] {
        guard !isSyncing else { return [] }
        isSyncing = true
        defer { isSyncing = false }

        let drafts = await health.runningWorkoutDrafts(limit: 400)
        let existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        var imported: [Run] = []
        var updated = 0

        for draft in drafts {
            guard draft.distanceMeters >= 200, draft.duration >= 60 else { continue }
            if let match = matchingRun(draft, in: existing + imported) {
                if enrich(match, with: draft) {
                    updated += 1
                }
                continue
            }
            let run = makeRun(from: draft)
            context.insert(run)
            imported.append(run)
            _ = RecordDetector.evaluate(run: run, context: context)
        }

        if !imported.isEmpty || updated > 0 {
            try? context.save()
        }
        lastImportedCount = imported.count
        lastUpdatedCount = updated
        lastSyncAt = .now
        if imported.isEmpty && updated == 0 {
            statusText = drafts.isEmpty
                ? "Noch keine externen Läufe in Apple Health gefunden. Adidas/Watch müssen in Health speichern, und NOCO braucht Lesezugriff."
                : "Alle bekannten Health-/Adidas-Läufe sind bereits in NOCO."
        } else if imported.isEmpty {
            statusText = "\(updated) Läufe aktualisiert (z. B. Puls/Strecke)."
        } else {
            let base = imported.count == 1
                ? "1 Lauf aus Apple Health / Adidas übernommen"
                : "\(imported.count) Läufe aus Apple Health / Adidas übernommen"
            statusText = updated > 0 ? "\(base), \(updated) aktualisiert." : "\(base)."
        }
        return imported
    }

    private func matchingRun(_ draft: HealthWorkoutDraft, in runs: [Run]) -> Run? {
        if let byUUID = runs.first(where: { $0.healthKitUUID == draft.uuid }) {
            return byUUID
        }
        return runs.first { run in
            guard run.status == .completed else { return false }
            let startDelta = abs(run.startedAt.timeIntervalSince(draft.startedAt))
            let distanceDelta = abs(run.distanceMeters - draft.distanceMeters)
            return startDelta < 180 && distanceDelta < max(150, draft.distanceMeters * 0.12)
        }
    }

    /// Fill missing BPM / route / calories on already imported Health runs.
    @discardableResult
    private func enrich(_ run: Run, with draft: HealthWorkoutDraft) -> Bool {
        var changed = false
        if run.healthKitUUID == nil {
            run.healthKitUUID = draft.uuid
            changed = true
        }
        if run.averageHeartRate == nil, let hr = draft.averageHeartRate, hr > 0 {
            run.averageHeartRate = hr
            changed = true
        }
        if run.calories == nil, let cal = draft.calories {
            run.calories = cal
            changed = true
        }
        if run.points.isEmpty, !draft.locations.isEmpty {
            for location in downsample(draft.locations) {
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
            if run.splits.isEmpty {
                for split in splits(from: draft.locations) {
                    split.run = run
                    run.splits.append(split)
                }
            }
            changed = true
        }
        if (run.routeName == nil || run.routeName?.isEmpty == true) {
            run.routeName = labeledSource(draft)
            changed = true
        }
        if run.notes == nil {
            run.notes = draft.sourceName
            changed = true
        }
        return changed
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
        run.routeName = labeledSource(draft)
        run.analysisPending = true

        for location in downsample(draft.locations) {
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

    private func labeledSource(_ draft: HealthWorkoutDraft) -> String {
        let blob = (draft.sourceName + " " + draft.bundleID).lowercased()
        if blob.contains("adidas") || blob.contains("runtastic") {
            return "adidas Running"
        }
        if blob.contains("apple") || draft.bundleID.lowercased().contains("com.apple") {
            return "Apple Watch / Health"
        }
        return draft.sourceName
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
        var segmentStart = locations[0].timestamp
        for location in locations.dropFirst() {
            travelled += location.distance(from: cursor)
            cursor = location
            if travelled >= Double(kmIndex) * 1000 {
                let duration = location.timestamp.timeIntervalSince(segmentStart)
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
                segmentStart = location.timestamp
                kmIndex += 1
            }
        }
        return result
    }
}
