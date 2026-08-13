import Foundation
import Combine
import CoreLocation

final class LocationEngine: NSObject, CLLocationManagerDelegate {
    struct Authorization {
        var whenInUse: Bool
        var always: Bool
        var denied: Bool
    }

    var onFix: ((RawFix) -> Void)?
    var onAuthorization: ((Authorization) -> Void)?
    var onError: ((Error) -> Void)?

    private let manager = CLLocationManager()
    private(set) var lastFix: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    var isReady: Bool {
        guard let lastFix else { return false }
        return lastFix.horizontalAccuracy > 0 && lastFix.horizontalAccuracy <= 35
    }

    var accuracy: Double? { lastFix?.horizontalAccuracy }

    func prepare() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
        manager.startUpdatingLocation()
    }

    func startTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func stop() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onAuthorization?(Authorization(
            whenInUse: status == .authorizedWhenInUse || status == .authorizedAlways,
            always: status == .authorizedAlways,
            denied: status == .denied || status == .restricted
        ))
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastFix = location
        let fix = RawFix(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            rawSpeed: max(0, location.speed)
        )
        onFix?(fix)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
    }
}
