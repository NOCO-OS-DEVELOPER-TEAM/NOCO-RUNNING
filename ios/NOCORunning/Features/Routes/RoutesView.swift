import SwiftUI
import SwiftData
import MapKit

struct RoutesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @State private var hint = ""

    private let presets: [(String, Double)] = [
        ("3 km", 3000),
        ("5 km", 5000),
        ("7,5 km", 7500),
        ("10 km", 10000)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !hint.isEmpty {
                        GlassSurface {
                            Text(hint).foregroundStyle(NocoTheme.mist)
                        }
                    }
                    Text("Vorschläge").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(presets, id: \.0) { preset in
                            Button {
                                env.tracker.prepareGPS()
                                env.tracker.start(routeName: preset.0)
                            } label: {
                                GlassSurface(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(preset.0).font(.title2.weight(.semibold))
                                        Text("Zielstrecke").font(.caption).foregroundStyle(NocoTheme.mist)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                        }
                    }

                    if !favorites.isEmpty {
                        Text("Favoriten").font(.headline)
                        ForEach(favorites, id: \.id) { route in
                            routeRow(route)
                        }
                    }

                    if !recent.isEmpty {
                        Text("Zuletzt").font(.headline)
                        ForEach(recent, id: \.id) { route in
                            routeRow(route)
                        }
                    }

                    NavigationLink("Eigene Strecke planen") {
                        RoutePlannerView()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .background(Color.clear)
            .navigationTitle("Strecken")
            .task {
                hint = await env.ai.recommendRoute(context: StatsMath.athleteContext(
                    name: env.athleteName,
                    weightKg: nil,
                    runs: StatsMath.completedRuns(runs),
                    goals: []
                ))
            }
        }
    }

    private var favorites: [SavedRoute] { routes.filter(\.isFavorite) }
    private var recent: [SavedRoute] { routes.filter { !$0.isFavorite } }

    private func routeRow(_ route: SavedRoute) -> some View {
        GlassSurface(cornerRadius: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text(route.name).font(.headline)
                    Text(RunFormatters.distanceWithUnit(route.distanceMeters, units: env.units))
                        .foregroundStyle(NocoTheme.mist)
                }
                Spacer()
                Button("Start") {
                    env.tracker.prepareGPS()
                    env.tracker.start(routeName: route.name)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct RoutePlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var startItem: MKMapItem?
    @State private var endItem: MKMapItem?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var distance: Double = 0
    @State private var name = "Meine Strecke"
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                if routeCoords.count >= 2 {
                    MapPolyline(coordinates: routeCoords)
                        .stroke(NocoTheme.aqua, lineWidth: 4)
                }
            }
            .frame(height: 280)
            List {
                TextField("Ort suchen", text: $query)
                    .onSubmit { Task { await search() } }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button(item.name ?? "Ort") {
                        assign(item)
                    }
                }
                if let startItem {
                    Text("Start: \(startItem.name ?? "")")
                }
                if let endItem {
                    Text("Ziel: \(endItem.name ?? "")")
                }
                TextField("Name", text: $name)
                if distance > 0 {
                    Text(RunFormatters.distanceWithUnit(distance, units: .metric))
                }
                Button("Strecke speichern") { save() }
                    .disabled(routeCoords.count < 2)
            }
        }
        .navigationTitle("Planen")
        .background(NocoTheme.ink)
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        results = ((try? await search.start())?.mapItems) ?? []
    }

    private func assign(_ item: MKMapItem) {
        if startItem == nil {
            startItem = item
        } else {
            endItem = item
            Task { await directions() }
        }
    }

    private func directions() async {
        guard let startItem, let endItem else { return }
        let request = MKDirections.Request()
        request.source = startItem
        request.destination = endItem
        request.transportType = .walking
        let directions = MKDirections(request: request)
        guard let route = try? await directions.calculate().routes.first else { return }
        routeCoords = route.polyline.coordinates
        distance = route.distance
        camera = .region(MKCoordinateRegion(route.polyline.boundingMapRect))
    }

    private func save() {
        let samples = routeCoords.map {
            CoordinateSample(timestamp: .now, latitude: $0.latitude, longitude: $0.longitude, altitude: 0, speedMPS: 0, accuracy: 0)
        }
        let route = SavedRoute(name: name, distanceMeters: distance, coordinates: samples)
        modelContext.insert(route)
        try? modelContext.save()
        dismiss()
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
