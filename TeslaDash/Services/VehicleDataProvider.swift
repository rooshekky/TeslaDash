import Foundation

/// Connection lifecycle surfaced by a vehicle data provider.
enum ProviderConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case handshaking
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning for car…"
        case .connecting: "Connecting…"
        case .handshaking: "Securing session…"
        case .connected: "Connected"
        case let .failed(message): "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Commands the UI can send to the vehicle. The provider translates these
/// into the underlying transport's command surface.
enum AppCommand: Sendable {
    case lock
    case unlock
    case wake
    case honk
    case flashLights
    case openTrunk
    case openFrunk
    case climateOn
    case climateOff
    case setTemperature(driverCelsius: Double, passengerCelsius: Double)
    case chargeStart
    case chargeStop
    case setChargeLimit(Int)
    case mediaToggle
    case mediaNext
    case mediaPrevious
    case mediaVolumeUp
    case mediaVolumeDown
}

/// A source of live vehicle state.
///
/// Implementations:
/// - `TeslaBLEProvider` — real car over Bluetooth LE (swift-tesla-ble).
/// - `DemoDataProvider` — simulated driving, for the simulator and for
///   trying the app without the car nearby.
///
/// Both publish the same `VehicleState` type, so the UI is identical.
protocol VehicleDataProvider: AnyObject {
    /// True for the simulated provider.
    var isDemo: Bool { get }

    /// Stream of fresh vehicle snapshots. Never finishes while the
    /// provider lives.
    var stateStream: AsyncStream<VehicleState> { get }

    /// Stream of connection-state transitions.
    var connectionStream: AsyncStream<ProviderConnectionState> { get }

    /// Bring the session up. For the BLE provider this scans, BLE-connects,
    /// and negotiates the per-domain session handshake.
    func connect() async throws

    /// Tear the session down.
    func disconnect() async

    /// Send a command to the vehicle.
    func send(_ command: AppCommand) async throws
}
