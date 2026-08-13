import SwiftUI
import Charts
import SwiftData

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "Woche"
    case month = "Monat"
    case year = "Jahr"
    var id: String { rawValue }
}

struct StatsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var range: StatsRange = .week

    private var completed: [Run] { StatsMath.completedRuns(runs) }
    private var start: Date {
        switch range {
        case .week: return StatsMath.weekStart()
        case .month: return StatsMath.monthStart()
        case .year: return StatsMath.yearStart()
        }
    }

    private var previousStart: Date {
        switch range {
        case .week: return Calendar.current.date(byAdding: .day, value: -7, to: start) ?? start
        case .month: return Calendar.current.date(byAdding: .month, value: -1, to: start) ?? start
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: start) ?? start
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let current = StatsMath.distance(completed, from: start)
                    let previous = StatsMath.distance(completed, from: previousStart, to: start)
                    GlassSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kilometer").font(NocoTheme.captionFont).foregroundStyle(NocoTheme.mist)
                            Text(RunFormatters.distanceWithUnit(current, units: env.units))
                                .font(NocoTheme.heroFont)
                                .contentTransition(.numericText(value: current))
                            Text("Vorher: \(RunFormatters.distanceWithUnit(previous, units: env.units))")
                                .foregroundStyle(NocoTheme.mist)
                        }
                    }
                    .animation(NocoMotion.soft, value: range)

                    distanceChart
                    paceCard
                    countCard
                }
                .padding(20)
            }
            .background(Color.clear)
            .navigationTitle("Statistik")
        }
    }

    private var buckets: [(label: String, meters: Double)] {
        let cal = Calendar.current
        switch range {
        case .week:
            return (0..<7).map { offset in
                let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.setLocalizedDateFormatFromTemplate("EEEEE")
                return (formatter.string(from: day), StatsMath.distance(completed, from: day, to: next))
            }
        case .month:
            let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
            return (0..<days).map { offset in
                let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
                return ("\(offset + 1)", StatsMath.distance(completed, from: day, to: next))
            }
        case .year:
            return (0..<12).map { offset in
                let month = cal.date(byAdding: .month, value: offset, to: start) ?? start
                let next = cal.date(byAdding: .month, value: 1, to: month) ?? month
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.setLocalizedDateFormatFromTemplate("MMM")
                return (formatter.string(from: month), StatsMath.distance(completed, from: month, to: next))
            }
        }
    }

    private var distanceChart: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Verlauf").font(.headline)
                Chart(buckets, id: \.label) { item in
                    BarMark(
                        x: .value("Zeit", item.label),
                        y: .value("km", item.meters / 1000)
                    )
                    .foregroundStyle(NocoTheme.aurora)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel().foregroundStyle(NocoTheme.mist)
                    }
                }
                .frame(height: 180)
                .animation(NocoMotion.soft, value: range)
            }
        }
    }

    private var paceCard: some View {
        let current = StatsMath.averagePace(completed, from: start)
        let previous = StatsMath.averagePace(completed, from: previousStart, to: start)
        return GlassSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pace").font(.headline)
                HStack {
                    Text(RunFormatters.pace(secondsPerKm: current, units: env.units))
                    Image(systemName: "arrow.right")
                        .foregroundStyle(NocoTheme.mist)
                    Text(RunFormatters.pace(secondsPerKm: previous, units: env.units))
                        .foregroundStyle(NocoTheme.mist)
                }
                .font(.title3.weight(.semibold))
            }
        }
    }

    private var countCard: some View {
        let count = completed.filter { $0.startedAt >= start }.count
        return GlassSurface {
            HStack {
                VStack(alignment: .leading) {
                    Text("Läufe").font(.headline)
                    Text("\(count) in diesem Zeitraum")
                        .foregroundStyle(NocoTheme.mist)
                }
                Spacer()
                Text("\(count)")
                    .font(NocoTheme.heroFont)
            }
        }
    }
}
