import Foundation

/// One completed drive, logged locally on-device.
///
/// The car exposes no trip-history API over BLE, so the app records trips
/// itself from the live drive state (see `TripLogger`).
struct Trip: Codable, Identifiable, Equatable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var distanceMiles: Double
    var durationSeconds: TimeInterval
    var startBatteryPercent: Int
    var endBatteryPercent: Int
    var startOdometerMiles: Double
    var endOdometerMiles: Double
    /// Estimated energy used, derived from battery-% delta and an assumed
    /// usable pack size. An estimate, not a metered value.
    var energyUsedKWh: Double

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        distanceMiles: Double,
        durationSeconds: TimeInterval,
        startBatteryPercent: Int,
        endBatteryPercent: Int,
        startOdometerMiles: Double,
        endOdometerMiles: Double,
        energyUsedKWh: Double
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.startBatteryPercent = startBatteryPercent
        self.endBatteryPercent = endBatteryPercent
        self.startOdometerMiles = startOdometerMiles
        self.endOdometerMiles = endOdometerMiles
        self.energyUsedKWh = energyUsedKWh
    }

    var averageSpeedMph: Double {
        guard durationSeconds > 0 else { return 0 }
        return distanceMiles / (durationSeconds / 3600)
    }
}

/// Tiny JSON persistence for trips, stored in the app's Documents directory.
/// No cloud, no account — trips never leave the phone.
enum TripStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trips.json")
    }

    static func load() -> [Trip] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Trip].self, from: data)) ?? []
    }

    static func save(_ trips: [Trip]) {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
