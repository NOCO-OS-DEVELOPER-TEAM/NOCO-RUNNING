import Foundation
import SwiftData

struct RecordDetector {
    @discardableResult
    static func evaluate(run: Run, context: ModelContext) -> [PersonalRecord] {
        guard run.status == .completed else { return [] }
        var fresh: [PersonalRecord] = []

        fresh += check(.longestRun, value: run.distanceMeters, run: run, context: context) { $0 > $1 }
        if let pace = run.averagePaceSecondsPerKm, run.distanceMeters >= 1000 {
            fresh += check(.bestPace, value: pace, run: run, context: context) { $0 < $1 }
            fresh += check(.fastestRun, value: pace, run: run, context: context) { $0 < $1 }
        }
        if let split = run.splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }) {
            fresh += check(.fastestKilometer, value: split.paceSecondsPerKm, run: run, context: context) { $0 < $1 }
        }

        let week = totalDistance(inLastDays: 7, context: context)
        let month = totalDistance(inLastDays: 31, context: context)
        fresh += check(.bestWeek, value: week, run: run, context: context) { $0 > $1 }
        fresh += check(.bestMonth, value: month, run: run, context: context) { $0 > $1 }

        try? context.save()
        return fresh
    }

    private static func check(
        _ kind: RecordKind,
        value: Double,
        run: Run,
        context: ModelContext,
        better: (Double, Double) -> Bool
    ) -> [PersonalRecord] {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.kindRaw == kindRaw })
        let existing = (try? context.fetch(descriptor))?.first
        if let existing {
            if better(value, existing.value) {
                existing.value = value
                existing.achievedAt = run.endedAt ?? run.startedAt
                existing.runID = run.id
                existing.celebrated = false
                return [existing]
            }
            return []
        }
        let record = PersonalRecord(kind: kind, value: value, achievedAt: run.endedAt ?? run.startedAt, runID: run.id)
        context.insert(record)
        return [record]
    }

    private static func totalDistance(inLastDays days: Int, context: ModelContext) -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.statusRaw == "completed" && $0.startedAt >= start })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.distanceMeters }
    }
}
