import Foundation

/// Gear (transmission) position reported by the car.
enum Gear: String, Sendable, CaseIterable {
    case park = "P"
    case reverse = "R"
    case neutral = "N"
    case drive = "D"

    var label: String { rawValue }
}

/// High-level charging session state.
enum ChargingStatus: String, Sendable, Equatable {
    case disconnected
    case charging
    case complete
    case stopped
    case starting

    var label: String {
        switch self {
        case .disconnected: "Not charging"
        case .charging: "Charging"
        case .complete: "Charge complete"
        case .stopped: "Charging stopped"
        case .starting: "Starting charge"
        }
    }
}

/// Per-wheel tire pressure reading.
struct TireReading: Sendable, Equatable {
    /// Pressure in PSI. Nil when the vehicle did not report this wheel.
    var psi: Double? = nil
    var hasWarning: Bool = false
}

/// App-level, provider-agnostic snapshot of everything the dashboard shows.
///
/// Both the live BLE provider and the demo provider produce this type, so
/// the UI never knows (or cares) where the data came from.
struct VehicleState: Sendable, Equatable {
    // MARK: Drive
    var speedMph: Double = 0
    var gear: Gear = .park
    var powerKW: Int = 0
    var odometerMiles: Double = 0

    // MARK: Battery / charging
    var batteryPercent: Int = 0
    var ratedRangeMiles: Double = 0
    var estimatedRangeMiles: Double = 0
    var chargingStatus: ChargingStatus = .disconnected
    var chargerPowerKW: Int = 0
    var chargerVoltage: Int = 0
    var chargerCurrent: Int = 0
    var minutesToFull: Int? = nil
    var chargeLimitPercent: Int = 80
    var chargePortOpen: Bool = false

    // MARK: Closures / security
    var locked: Bool = true
    var frontLeftDoorOpen: Bool = false
    var frontRightDoorOpen: Bool = false
    var rearLeftDoorOpen: Bool = false
    var rearRightDoorOpen: Bool = false
    var frunkOpen: Bool = false
    var trunkOpen: Bool = false
    var sentryMode: Bool = false
    var isUserPresent: Bool = false
    var carAwake: Bool = true

    // MARK: Climate
    var insideTempCelsius: Double? = nil
    var outsideTempCelsius: Double? = nil
    var climateOn: Bool = false
    var driverTempCelsius: Double? = nil

    // MARK: Tires
    var tireFrontLeft: TireReading = TireReading()
    var tireFrontRight: TireReading = TireReading()
    var tireRearLeft: TireReading = TireReading()
    var tireRearRight: TireReading = TireReading()
    var recommendedFrontPSI: Double? = nil
    var recommendedRearPSI: Double? = nil

    // MARK: Media
    var mediaArtist: String? = nil
    var mediaTitle: String? = nil
    var mediaAlbum: String? = nil
    var mediaSource: String? = nil
    var mediaVolumeFraction: Double? = nil

    // MARK: Position (demo provider fills these; live mode uses the
    // phone's GPS via LocationProvider — the library's snapshot does not
    // expose the car's LocationState).
    var latitude: Double? = nil
    var longitude: Double? = nil
    var headingDegrees: Double? = nil

    // MARK: Meta
    var firmwareVersion: String? = nil
    var lastUpdated: Date = Date()

    /// Any door, trunk, or frunk currently open.
    var anyOpeningOpen: Bool {
        frontLeftDoorOpen || frontRightDoorOpen || rearLeftDoorOpen || rearRightDoorOpen
            || frunkOpen || trunkOpen
    }
}
