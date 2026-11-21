import SwiftUI

/// Locally logged trips. The car has no trip-history API over BLE, so
/// these are recorded on-device by `TripLogger` and never leave the phone.
struct TripHistoryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var tripLogger: TripLogger

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        self._tripLogger = ObservedObject(wrappedValue: viewModel.tripLogger)
    }

    var body: some View {
        NavigationStack {
            Group {
                if tripLogger.trips.isEmpty {
                    ContentUnavailableView(
                        "No trips yet",
                        systemImage: "car",
                        description: Text("Trips are recorded automatically while you drive. Take the car for a spin — or run demo mode — and they'll show up here.")
                    )
                } else {
                    List {
                        ForEach(tripLogger.trips) { trip in
                            TripRow(trip: trip)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                tripLogger.deleteTrip(tripLogger.trips[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                if !tripLogger.trips.isEmpty {
                    Button("Clear all", role: .destructive) {
                        tripLogger.deleteAllTrips()
                    }
                }
            }
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.startDate, style: .date)
                    .font(.headline)
                Spacer()
                Text("\(String(format: "%.1f", trip.distanceMiles)) mi")
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack(spacing: 16) {
                Label(formattedDuration, systemImage: "clock")
                Label("\(Int(trip.averageSpeedMph)) mph avg", systemImage: "gauge.with.dots.needle.50percent")
                Label("\(String(format: "%.1f", trip.energyUsedKWh)) kWh", systemImage: "bolt.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("\(trip.startDate, style: .time) → \(trip.endDate, style: .time) · Battery \(trip.startBatteryPercent)% → \(trip.endBatteryPercent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDuration: String {
        let minutes = Int(trip.durationSeconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
