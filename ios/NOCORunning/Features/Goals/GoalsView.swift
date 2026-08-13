import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var kind: GoalKind = .weeklyDistance
    @State private var value: Double = 20

    var body: some View {
        Form {
            Section("Aktiv") {
                ForEach(goals.filter(\.isActive), id: \.createdAt) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(goal.kind.title).font(.headline)
                        ProgressRing(progress: progress(for: goal), label: display(goal), detail: "")
                    }
                }
            }
            Section("Neues Ziel") {
                Picker("Art", selection: $kind) {
                    ForEach(GoalKind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Wert", value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Button("Speichern") {
                    let stored: Double
                    switch kind {
                    case .weeklyDistance, .monthlyDistance, .targetDistance:
                        stored = value * 1000
                    case .targetPace:
                        stored = value * 60
                    case .weeklyRuns:
                        stored = value
                    }
                    modelContext.insert(Goal(kind: kind, targetValue: stored))
                    try? modelContext.save()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Ziele")
    }

    private func progress(for goal: Goal) -> Double {
        let current: Double
        switch goal.kind {
        case .weeklyDistance:
            current = StatsMath.distance(runs, from: StatsMath.weekStart())
        case .monthlyDistance:
            current = StatsMath.distance(runs, from: StatsMath.monthStart())
        case .weeklyRuns:
            current = Double(StatsMath.completedRuns(runs).filter { $0.startedAt >= StatsMath.weekStart() }.count)
        case .targetDistance:
            current = StatsMath.completedRuns(runs).first?.distanceMeters ?? 0
        case .targetPace:
            current = StatsMath.averagePace(runs, from: StatsMath.weekStart()) ?? goal.targetValue
        }
        guard goal.targetValue > 0 else { return 0 }
        if goal.kind == .targetPace {
            return min(goal.targetValue / max(current, 1), 1)
        }
        return min(current / goal.targetValue, 1)
    }

    private func display(_ goal: Goal) -> String {
        switch goal.kind {
        case .weeklyDistance, .monthlyDistance, .targetDistance:
            return RunFormatters.distanceWithUnit(goal.targetValue, units: .metric)
        case .weeklyRuns:
            return "\(Int(goal.targetValue)) Läufe"
        case .targetPace:
            return RunFormatters.paceClock(goal.targetValue) + " min/km"
        }
    }
}

struct RecordsView: View {
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        List {
            ForEach(RecordKind.allCases, id: \.rawValue) { kind in
                if let record = records.first(where: { $0.kind == kind }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(kind.title).font(.headline)
                            Text(RunFormatters.relativeDate(record.achievedAt))
                                .font(.caption)
                                .foregroundStyle(NocoTheme.mist)
                        }
                        Spacer()
                            Text(valueText(record))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NocoTheme.ink)
        .navigationTitle("Rekorde")
    }

    private func valueText(_ record: PersonalRecord) -> String {
        switch record.kind {
        case .longestRun, .bestWeek, .bestMonth:
            return RunFormatters.distanceWithUnit(record.value, units: env.units)
        case .fastestRun, .bestPace, .fastestKilometer:
            return RunFormatters.paceClock(record.value)
        }
    }
}
