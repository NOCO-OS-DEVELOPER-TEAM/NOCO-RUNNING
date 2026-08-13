import SwiftUI
import MapKit

struct RunSummaryView: View {
    var run: Run
    var onDone: () -> Void
    @EnvironmentObject private var env: AppEnvironment
    @State private var revealed = 0
    @State private var showRecords = false

    private var units: UnitSystem { env.units }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero.opacity(revealed >= 1 ? 1 : 0).offset(y: revealed >= 1 ? 0 : 12)
                    metrics.opacity(revealed >= 2 ? 1 : 0)
                    if !run.points.isEmpty {
                        miniMap.opacity(revealed >= 3 ? 1 : 0)
                    }
                    splits.opacity(revealed >= 4 ? 1 : 0)
                    if let body = run.analysisBody {
                        GlassSurface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(run.analysisTitle ?? "Coach")
                                    .font(.headline)
                                Text(body)
                                    .foregroundStyle(NocoTheme.mist)
                            }
                        }
                        .opacity(revealed >= 5 ? 1 : 0)
                    }
                    if showRecords {
                        ForEach(env.newRecords, id: \.kindRaw) { record in
                            GlassSurface {
                                HStack {
                                    Image(systemName: "sparkle")
                                        .foregroundStyle(NocoTheme.sun)
                                    Text("Neuer Rekord: \(record.kind.title)")
                                        .font(.headline)
                                }
                            }
                            .rainbowGlow(opacity: 0.6)
                        }
                    }
                }
                .padding(20)
                .animation(NocoMotion.soft, value: revealed)
            }
            .background(Color.clear)
            .navigationTitle("Dein Lauf")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: onDone)
                }
            }
            .onAppear { animateIn() }
        }
    }

    private var hero: some View {
        GlassSurface(cornerRadius: 32, bloom: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(RunFormatters.relativeDate(run.startedAt))
                    .font(NocoTheme.captionFont)
                    .foregroundStyle(NocoTheme.mist)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RunFormatters.distance(run.distanceMeters, units: units))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(units.distanceLabel)
                        .font(.title2)
                        .foregroundStyle(NocoTheme.mist)
                }
                HStack {
                    Label(RunFormatters.duration(run.durationSeconds), systemImage: "clock")
                    Spacer()
                    Label(RunFormatters.pace(secondsPerKm: run.averagePaceSecondsPerKm, units: units), systemImage: "speedometer")
                }
                .font(.title3.weight(.semibold))
            }
        }
        .rainbowGlow(opacity: 0.4)
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryTile("Schnitt", RunFormatters.speed(metersPerSecond: run.averageSpeedMPS, units: units) + " \(units.speedLabel)")
            summaryTile("Kalorien", RunFormatters.calories(run.calories) + " kcal")
            summaryTile("Höhenmeter", RunFormatters.elevation(run.elevationGainMeters))
            summaryTile("Puls", RunFormatters.heartRate(run.averageHeartRate) + " bpm")
            if let split = run.splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }) {
                summaryTile("Schnellster km", RunFormatters.paceClock(split.paceSecondsPerKm))
            }
            if let split = run.splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }) {
                summaryTile("Langsamster km", RunFormatters.paceClock(split.paceSecondsPerKm))
            }
            if let temp = run.weatherTempC {
                summaryTile("Wetter", "\(Int(temp.rounded()))°")
            }
        }
    }

    private var miniMap: some View {
        let coords = run.points.sorted { $0.timestamp < $1.timestamp }.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        return Map {
            if coords.count >= 2 {
                MapPolyline(coordinates: coords)
                    .stroke(NocoTheme.violet, lineWidth: 4)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .disabled(true)
    }

    @ViewBuilder
    private var splits: some View {
        if !run.splits.isEmpty {
            GlassSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kilometer").font(.headline)
                    ForEach(run.splits.sorted { $0.kilometerIndex < $1.kilometerIndex }, id: \.kilometerIndex) { split in
                        HStack {
                            Text("km \(split.kilometerIndex)")
                            Spacer()
                            Text(RunFormatters.paceClock(split.paceSecondsPerKm))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func summaryTile(_ title: String, _ value: String) -> some View {
        GlassSurface(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(NocoTheme.captionFont).foregroundStyle(NocoTheme.mist)
                Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func animateIn() {
        for step in 1...5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.18) {
                revealed = step
            }
        }
        if !env.newRecords.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                showRecords = true
                Haptics.record()
            }
        }
    }
}
