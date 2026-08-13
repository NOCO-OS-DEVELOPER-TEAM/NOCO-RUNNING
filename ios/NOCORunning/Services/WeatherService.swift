import Foundation
import CoreLocation

struct WeatherSnapshot: Equatable {
    var temperatureC: Double
    var symbol: String
    var windKmh: Double?
    var conditionLabel: String
}

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var current: WeatherSnapshot?

    func refresh(latitude: Double, longitude: Double) async {
        // WeatherKit requires a paid Apple capability. Keep weather optional and never block a run.
        current = nil
        _ = CLLocation(latitude: latitude, longitude: longitude)
    }

    func attach(to run: Run) {
        guard let current else { return }
        run.weatherTempC = current.temperatureC
        run.weatherSymbol = current.symbol
    }
}
