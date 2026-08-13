import Foundation
import SwiftData

enum StatsMath {
    static func completedRuns(_ runs: [Run]) -> [Run] {
        runs.filter { $0.status == .completed }.sorted { $0.startedAt > $1.startedAt }
    }

    static func distance(_ runs: [Run], from start: Date, to end: Date = .now) -> Double {
        completedRuns(runs)
            .filter { $0.startedAt >= start && $0.startedAt < end }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    static func duration(_ runs: [Run], from start: Date, to end: Date = .now) -> TimeInterval {
        completedRuns(runs)
            .filter { $0.startedAt >= start && $0.startedAt < end }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    static func averagePace(_ runs: [Run], from start: Date, to end: Date = .now) -> Double? {
        let slice = completedRuns(runs).filter { $0.startedAt >= start && $0.startedAt < end && $0.distanceMeters > 400 }
        let meters = slice.reduce(0) { $0 + $1.distanceMeters }
        let seconds = slice.reduce(0) { $0 + $1.durationSeconds }
        return PaceMath.secondsPerKm(distanceMeters: meters, duration: seconds)
    }

    static func weekStart(for date: Date = .now) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    static func monthStart(for date: Date = .now) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    static func yearStart(for date: Date = .now) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year], from: date)) ?? date
    }

    static func typicalPace(from runs: [Run]) -> Double? {
        let paces = completedRuns(runs).compactMap(\.averagePaceSecondsPerKm)
        guard !paces.isEmpty else { return nil }
        let sorted = paces.sorted()
        return sorted[sorted.count / 2]
    }

    static func typicalDistance(from runs: [Run]) -> Double? {
        let distances = completedRuns(runs).map(\.distanceMeters).filter { $0 > 0 }
        guard !distances.isEmpty else { return nil }
        let sorted = distances.sorted()
        return sorted[sorted.count / 2]
    }

    static func athleteContext(name: String, weightKg: Double?, runs: [Run], goals: [Goal]) -> AthleteContext {
        let completed = completedRuns(runs)
        return AthleteContext(
            athleteName: name,
            weightKg: weightKg,
            weekDistanceMeters: distance(runs, from: weekStart()),
            monthDistanceMeters: distance(runs, from: monthStart()),
            typicalPaceSecondsPerKm: typicalPace(from: runs),
            typicalDistanceMeters: typicalDistance(from: runs),
            runCount: completed.count,
            goals: goals.filter(\.isActive).map { "\($0.kind.title): \($0.targetValue)" },
            recentRuns: Array(completed.prefix(12).map { $0.toDTO() }),
            question: nil
        )
    }
}
