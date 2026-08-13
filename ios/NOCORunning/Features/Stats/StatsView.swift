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
    @State private var appear = false

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
                    GlassSurface(cornerRadius: 28, bloom: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                IntelligenceSparkle()
                                Text("Kilometer").font(NocoTheme.captionFont).foregroundStyle(NocoTheme.mist)
                            }
                            Text(RunFormatters.distanceWithUnit(current, units: env.units))
                                .font(NocoTheme.heroFont)
                                .contentTransition(.numericText(value: current))
                            Text("Vorher: \(RunFormatters.distanceWithUnit(previous, units: env.units))")
                                .foregroundStyle(NocoTheme.mist)
                        }
                    }
                    .animation(NocoMotion.soft, value: range)

                    distanceChart
                    paceLineChart
                    sourceMixChart
                    paceCard
                    countCard
                }
                .padding(20)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
            }
            .background(Color.clear)
            .navigationTitle("Statistik")
            .onAppear {
                withAnimation(NocoMotion.soft) { appear = true }
            }
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
            return stride(from: 0, to: days, by: max(1, days / 10)).map { offset in
                let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                let next = cal.date(byAdding: .day, value: max(1, days / 10), to: day) ?? day
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
                Text("Distanz").font(.headline)
                Chart(buckets, id: \.label) { item in
                    BarMark(
                        x: .value("Zeit", item.label),
                        y: .value("km", appear ? item.meters / 1000 : 0)
                    )
                    .foregroundStyle(NocoTheme.aurora)
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel().foregroundStyle(NocoTheme.mist)
                    }
                }
                .frame(height: 190)
                .animation(NocoMotion.soft, value: range)
                .animation(NocoMotion.soft, value: appear)
            }
        }
        .rainbowGlow(radius: 10, opacity: 0.25)
    }

    private var paceLineChart: some View {
        let points = completed
            .filter { $0.startedAt >= start }
            .compactMap { run -> (Date, Double)? in
                guard let pace = run.averagePaceSecondsPerKm else { return nil }
                return (run.startedAt, pace)
            }
            .suffix(16)
        return GlassSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pace-Kurve").font(.headline)
                if points.isEmpty {
                    Text("Noch zu wenig Läufe für eine Kurve.")
                        .foregroundStyle(NocoTheme.mist)
                } else {
                    Chart(Array(points), id: \.0) { item in
                        LineMark(
                            x: .value("Datum", item.0),
                            y: .value("s/km", appear ? item.1 : item.1 * 1.08)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(NocoTheme.aqua)
                        AreaMark(
                            x: .value("Datum", item.0),
                            y: .value("s/km", appear ? item.1 : item.1 * 1.08)
                        )
                        .foregroundStyle(NocoTheme.aqua.opacity(0.15))
                    }
                    .frame(height: 160)
                    .animation(NocoMotion.soft, value: range)
                }
            }
        }
    }

    private var sourceMixChart: some View {
        let slice = completed.filter { $0.startedAt >= start }
        let noco = slice.filter { $0.source == .tracked }.count
        let health = slice.filter { $0.source == .appleHealth }.count
        let imported = slice.filter { $0.source == .imported || $0.source == .manual }.count
        let data: [(String, Int)] = [
            ("NOCO", noco),
            ("Health/Adidas", health),
            ("Import", imported)
        ].filter { $0.1 > 0 }

        return GlassSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quellen").font(.headline)
                if data.isEmpty {
                    Text("Noch keine Läufe in diesem Zeitraum.")
                        .foregroundStyle(NocoTheme.mist)
                } else {
                    Chart(data, id: \.0) { item in
                        SectorMark(
                            angle: .value("Läufe", appear ? item.1 : 0),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Quelle", item.0))
                    }
                    .frame(height: 180)
                    .chartLegend(position: .bottom)
                    .animation(NocoMotion.soft, value: appear)
                }
            }
        }
        .rainbowGlow(radius: 8, opacity: 0.2)
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
        return GlassSurface(bloom: true) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Läufe").font(.headline)
                    Text("\(count) in diesem Zeitraum · für den Coach synchronisiert")
                        .foregroundStyle(NocoTheme.mist)
                }
                Spacer()
                Text("\(count)")
                    .font(NocoTheme.heroFont)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
    }
}
