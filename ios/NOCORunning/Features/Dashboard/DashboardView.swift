import SwiftUI
import SwiftData

struct DashboardView: View {
    var onStart: () -> Void
    @EnvironmentObject private var env: AppEnvironment
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query private var goals: [Goal]
    @Query private var records: [PersonalRecord]

    private var completed: [Run] { StatsMath.completedRuns(runs) }
    private var units: UnitSystem { env.units }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    startButton
                    dynamicCards
                }
                .padding(20)
            }
            .background(Color.clear)
            .navigationTitle("NOCO")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AIStatusDot(status: env.ai.reachability)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(NocoTheme.mist)
            Text(env.athleteName.isEmpty ? "Bereit zum Laufen" : env.athleteName)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
    }

    private var hero: some View {
        GlassSurface(cornerRadius: 32, bloom: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    IntelligenceSparkle()
                    Text(heroTitle)
                        .font(NocoTheme.captionFont)
                        .tracking(1.2)
                        .foregroundStyle(NocoTheme.mist)
                }
                HStack(alignment: .bottom, spacing: 20) {
                    MetricStack(
                        label: units.distanceLabel,
                        value: RunFormatters.distance(heroDistance, units: units),
                        emphasis: true
                    )
                    Spacer()
                    MetricStack(label: "Zeit", value: RunFormatters.duration(heroDuration))
                    MetricStack(
                        label: "Pace",
                        value: RunFormatters.paceClock(heroPace ?? 0)
                    )
                }
            }
        }
        .rainbowGlow(radius: 18, opacity: 0.5)
    }

    private var startButton: some View {
        AuroraButton(title: "Lauf starten", systemImage: "figure.run") {
            Haptics.medium()
            onStart()
        }
    }

    @ViewBuilder
    private var dynamicCards: some View {
        if env.healthSync.lastImportedCount > 0 {
            GlassSurface {
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundStyle(NocoTheme.aqua)
                    Text(env.healthSync.statusText)
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        if let last = completed.first {
            lastRunCard(last)
        }
        weekCard
        if let insight = completed.first(where: { $0.analysisBody != nil }) {
            insightCard(insight)
        }
        if let record = records.sorted(by: { $0.achievedAt > $1.achievedAt }).first {
            recordCard(record)
        }
        if let weight = weights.first {
            GlassSurface {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gewicht").font(NocoTheme.captionFont).foregroundStyle(NocoTheme.mist)
                        Text(String(format: "%.1f kg", weight.kilograms).replacingOccurrences(of: ".", with: ","))
                            .font(NocoTheme.metricFont)
                    }
                    Spacer()
                    Image(systemName: "scalemass")
                        .foregroundStyle(NocoTheme.violet)
                }
            }
        }
    }

    private func lastRunCard(_ run: Run) -> some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("Letzter Lauf · \(RunFormatters.relativeDate(run.startedAt)) · \(run.source.title)")
                    .font(NocoTheme.captionFont)
                    .foregroundStyle(NocoTheme.mist)
                HStack {
                    Text(RunFormatters.distanceWithUnit(run.distanceMeters, units: units))
                    Spacer()
                    Text(RunFormatters.duration(run.durationSeconds))
                    Spacer()
                    Text(RunFormatters.pace(secondsPerKm: run.averagePaceSecondsPerKm, units: units))
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
        }
    }

    private var weekCard: some View {
        let week = StatsMath.distance(completed, from: StatsMath.weekStart())
        let goal = goals.first(where: { $0.kind == .weeklyDistance && $0.isActive })?.targetValue ?? 20_000
        return GlassSurface {
            ProgressRing(
                progress: goal == 0 ? 0 : week / goal,
                label: "Diese Woche",
                detail: "\(RunFormatters.distanceWithUnit(week, units: units)) von \(RunFormatters.distanceWithUnit(goal, units: units))"
            )
        }
    }

    private func insightCard(_ run: Run) -> some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text(run.analysisTitle ?? "KI-Erkenntnis")
                    .font(.headline)
                Text(run.analysisBody ?? "")
                    .font(.subheadline)
                    .foregroundStyle(NocoTheme.mist)
                    .lineLimit(4)
            }
        }
    }

    private func recordCard(_ record: PersonalRecord) -> some View {
        GlassSurface {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persönlicher Rekord").font(NocoTheme.captionFont).foregroundStyle(NocoTheme.mist)
                    Text(record.kind.title).font(.headline)
                }
                Spacer()
                Image(systemName: "sparkle")
                    .foregroundStyle(NocoTheme.sun)
            }
        }
        .rainbowGlow(radius: 10, opacity: 0.4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11: return "Guten Morgen"
        case 11..<17: return "Bereit für die nächste Runde"
        case 17..<22: return "Schöner Abend zum Laufen"
        default: return "Noch unterwegs?"
        }
    }

    private var todayRuns: [Run] {
        completed.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    private var heroDistance: Double {
        if !todayRuns.isEmpty {
            return todayRuns.reduce(0) { $0 + $1.distanceMeters }
        }
        return StatsMath.distance(completed, from: StatsMath.weekStart())
    }

    private var heroDuration: TimeInterval {
        if !todayRuns.isEmpty {
            return todayRuns.reduce(0) { $0 + $1.durationSeconds }
        }
        return StatsMath.duration(completed, from: StatsMath.weekStart())
    }

    private var heroPace: Double? {
        if !todayRuns.isEmpty {
            return StatsMath.averagePace(todayRuns, from: Calendar.current.startOfDay(for: .now))
        }
        return StatsMath.averagePace(completed, from: StatsMath.weekStart())
    }

    private var heroTitle: String {
        todayRuns.isEmpty ? "DIESE WOCHE" : "HEUTE"
    }
}

struct AIStatusDot: View {
    var status: AIReachability

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(NocoTheme.mist)
        }
    }

    private var color: Color {
        switch status {
        case .connected: return NocoTheme.aqua
        case .unreachable: return NocoTheme.coral
        case .unknown: return NocoTheme.mist.opacity(0.4)
        }
    }

    private var label: String {
        switch status {
        case .connected: return "KI"
        case .unreachable: return "KI offline"
        case .unknown: return "KI"
        }
    }
}
