import Foundation

/// Records trips locally from the live drive state.
///
/// The car exposes no trip-history API over BLE, so the app logs trips
/// itself: a trip starts when the car begins driving and ends after it
/// has been parked for 60 seconds (or when the session disconnects).
/// Trips are stored in `trips.json` in Documents — they never leave the
/// phone.
///
/// Energy use is an estimate: battery-% delta × an assumed 75 kWh usable
/// pack (2024 Model 3 Highland, Long Range-ish). It is not metered.
@MainActor
final class TripLogger: ObservableObject {
    @Published private(set) var trips: [Trip] = TripStore.load()

    /// Assumed usable pack size for the energy estimate (kWh).
    private let usableBatteryKWh: Double = 75

    private struct ActiveTrip {
        var startDate: Date
        var startBatteryPercent: Int
        var startOdometerMiles: Double
        var maxSpeedMph: Double
    }

    private var activeTrip: ActiveTrip?
    private var parkedSince: Date?
    private var lastState: VehicleState?

    /// Feed every fresh `VehicleState` here; the logger decides when a
    /// trip starts, continues, and ends.
    func observe(_ state: VehicleState) {
        defer { lastState = state }

        let driving = state.gear == .drive && state.speedMph > 1

        if driving {
            parkedSince = nil
            if activeTrip == nil {
                activeTrip = ActiveTrip(
                    startDate: Date(),
                    startBatteryPercent: state.batteryPercent,
                    startOdometerMiles: state.odometerMiles,
                    maxSpeedMph: state.speedMph
                )
            } else {
                activeTrip?.maxSpeedMph = max(activeTrip?.maxSpeedMph ?? 0, state.speedMph)
            }
            return
        }

        // Parked.
        if activeTrip != nil {
            if parkedSince == nil { parkedSince = Date() }
            if let parkedSince, Date().timeIntervalSince(parkedSince) >= 60 {
                finishTrip(endState: state)
            }
        }
    }

    /// Call on disconnect so an in-progress trip is saved, not lost.
    func flush() {
        if let state = lastState, activeTrip != nil {
            finishTrip(endState: state)
        }
    }

    func deleteTrip(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        TripStore.save(trips)
    }

    func deleteAllTrips() {
        trips = []
        TripStore.save(trips)
    }

    private func finishTrip(endState: VehicleState) {
        guard let active = activeTrip else { return }
        activeTrip = nil
        parkedSince = nil

        let distance = max(0, endState.odometerMiles - active.startOdometerMiles)
        let duration = Date().timeIntervalSince(active.startDate)
        // Ignore implausibly short "trips" (e.g. shuffling in a driveway).
        guard distance >= 0.1 || duration >= 120 else { return }

        let batteryDelta = max(0, active.startBatteryPercent - endState.batteryPercent)
        let trip = Trip(
            startDate: active.startDate,
            endDate: Date(),
            distanceMiles: distance,
            durationSeconds: duration,
            startBatteryPercent: active.startBatteryPercent,
            endBatteryPercent: endState.batteryPercent,
            startOdometerMiles: active.startOdometerMiles,
            endOdometerMiles: endState.odometerMiles,
            energyUsedKWh: Double(batteryDelta) / 100 * usableBatteryKWh
        )
        trips.insert(trip, at: 0)
        TripStore.save(trips)
    }
}
