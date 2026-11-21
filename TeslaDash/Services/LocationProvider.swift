import CoreLocation
import Foundation

/// The phone's own GPS, used for the live map.
///
/// Why phone GPS and not the car's? The swift-tesla-ble snapshot type
/// (`TeslaVehicleSnapshot`) does not expose the car's `LocationState`
/// category, so the reliable source is the iPhone itself — which is in
/// the car while the dashboard is running, so the position is the same.
/// (The car reports no heading over this path either; the demo provider
/// simulates one, and the map follows the phone's heading.)
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 5
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }
}
