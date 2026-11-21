import Combine
import Foundation
import MapKit
import TeslaBLE
import UIKit

/// The app's single source of truth, owned by `ContentView`.
///
/// Owns the active `VehicleDataProvider` (live BLE or demo), the trip
/// logger, the location provider, navigation state, and all persisted
/// user preferences. Views read `@Published` state and call the small
/// action methods — they never touch the BLE layer directly.
@MainActor
final class DashboardViewModel: ObservableObject {
    enum AppMode: String {
        case live
        case demo
    }

    // MARK: - Published state

    @Published var vehicleState = VehicleState()
    @Published var connection: ProviderConnectionState = .disconnected
    @Published var mode: AppMode = .demo
    @Published var isPaired: Bool
    @Published var vin: String
    @Published var errorMessage: String?
    @Published var leftPanel: PanelKind
    @Published var rightPanel: PanelKind
    @Published var useMetricUnits: Bool {
        didSet { UserDefaults.standard.set(useMetricUnits, forKey: "useMetricUnits") }
    }
    @Published var route: MKRoute?
    @Published var destinationName: String?
    @Published var isRouting = false

    // MARK: - Services

    let locationProvider = LocationProvider()
    let tripLogger = TripLogger()
    let pairingService = PairingService()

    // MARK: - Private

    private var provider: (any VehicleDataProvider)?
    private var stateTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Estimated consumption used for battery-on-arrival: ~0.33% of pack
    /// per mile ≈ 300 miles of usable range (2024 Model 3 Highland).
    /// An estimate, not a measurement.
    private let batteryPercentPerMile = 0.33

    init() {
        let savedVIN = UserDefaults.standard.string(forKey: "pairedVIN") ?? ""
        vin = savedVIN
        isPaired = !savedVIN.isEmpty
        useMetricUnits = UserDefaults.standard.bool(forKey: "useMetricUnits")
        leftPanel = PanelKind(rawValue: UserDefaults.standard.string(forKey: "leftPanel") ?? "") ?? .map
        rightPanel = PanelKind(rawValue: UserDefaults.standard.string(forKey: "rightPanel") ?? "") ?? .music

        // Forward location updates so views reading `mapCoordinate` refresh
        // when the phone's GPS moves. The hop into a Task keeps the
        // Combine sink closure free of MainActor-isolation questions.
        locationProvider.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Start the current mode's provider (demo by default).
    func start() async {
        await switchToMode(mode)
    }

    func switchToMode(_ newMode: AppMode) async {
        await stopProvider()
        mode = newMode
        if newMode == .demo {
            let demo = DemoDataProvider()
            provider = demo
            observe(provider: demo)
            do {
                try await demo.connect()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            guard isPaired else {
                // ContentView shows the pairing flow when live mode is
                // selected without a paired car.
                return
            }
            let live = TeslaBLEProvider(vin: vin)
            provider = live
            observe(provider: live)
            locationProvider.requestAuthorization()
            locationProvider.start()
            do {
                try await live.connect()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reconnect() async {
        await switchToMode(mode)
    }

    func disconnect() async {
        await stopProvider()
        connection = .disconnected
    }

    private func stopProvider() async {
        stateTask?.cancel()
        connectionTask?.cancel()
        stateTask = nil
        connectionTask = nil
        tripLogger.flush()
        await provider?.disconnect()
        provider = nil
        locationProvider.stop()
    }

    private func observe(provider: any VehicleDataProvider) {
        stateTask = Task {
            for await state in provider.stateStream {
                vehicleState = state
                tripLogger.observe(state)
            }
        }
        connectionTask = Task {
            for await conn in provider.connectionStream {
                connection = conn
            }
        }
    }

    // MARK: - Commands

    func sendCommand(_ command: AppCommand) async {
        do {
            try await provider?.send(command)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pairing

    func refreshPairedState() {
        let savedVIN = UserDefaults.standard.string(forKey: "pairedVIN") ?? ""
        vin = savedVIN
        isPaired = !savedVIN.isEmpty
    }

    func unpair() async {
        await stopProvider()
        let keyStore = KeychainTeslaKeyStore(service: "com.tesladash.app")
        try? keyStore.deletePrivateKey(forVIN: vin)
        UserDefaults.standard.removeObject(forKey: "pairedVIN")
        vin = ""
        isPaired = false
        await switchToMode(.demo)
    }

    // MARK: - Panels & units

    func setLeftPanel(_ panel: PanelKind) {
        leftPanel = panel
        UserDefaults.standard.set(panel.rawValue, forKey: "leftPanel")
    }

    func setRightPanel(_ panel: PanelKind) {
        rightPanel = panel
        UserDefaults.standard.set(panel.rawValue, forKey: "rightPanel")
    }

    /// Keep the screen awake while the dashboard is up (a dashboard app
    /// must not dim mid-drive). Callers restore it on disappear.
    func setScreenAwake(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }

    // MARK: - Map & navigation

    /// Best available position for the map: the demo simulation's
    /// coordinate in demo mode, otherwise the phone's GPS (the phone is
    /// in the car, so this is the car's position).
    var mapCoordinate: CLLocationCoordinate2D? {
        if let lat = vehicleState.latitude, let lon = vehicleState.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return locationProvider.location?.coordinate
    }

    var routeDestinationCoordinate: CLLocationCoordinate2D? {
        route?.polyline.coordinates.last
    }

    /// Estimated battery % remaining on arrival, from route distance.
    /// Estimate only — see `batteryPercentPerMile`.
    var batteryOnArrivalPercent: Int? {
        guard let route else { return nil }
        let miles = route.distance / 1609.34
        let used = miles * batteryPercentPerMile
        return max(0, Int(Double(vehicleState.batteryPercent) - used))
    }

    var routeETA: String? {
        guard let route else { return nil }
        let arrival = Date().addingTimeInterval(route.expectedTravelTime)
        return DateFormatter.localizedString(from: arrival, dateStyle: .none, timeStyle: .short)
    }

    func requestRoute(to destination: MKMapItem) async {
        guard let origin = mapCoordinate else {
            errorMessage = "No location yet — wait for GPS or demo position."
            return
        }
        isRouting = true
        defer { isRouting = false }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = destination
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            if let first = response.routes.first {
                route = first
                destinationName = destination.name
            } else {
                errorMessage = "No route found to that destination."
            }
        } catch {
            errorMessage = "Routing failed: \(error.localizedDescription)"
        }
    }

    func clearRoute() {
        route = nil
        destinationName = nil
    }
}

// MARK: - MKPolyline helper

private extension MKPolyline {
    /// All coordinates of the polyline, for the destination marker.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
