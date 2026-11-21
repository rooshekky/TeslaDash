import SwiftUI

/// Per-wheel tire pressures, shown as a top-down car diagram.
struct TirePressureView: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var state: VehicleState { viewModel.vehicleState }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                tireCell(label: "Front left", reading: state.tireFrontLeft)
                tireCell(label: "Front right", reading: state.tireFrontRight)
            }
            HStack(spacing: 24) {
                tireCell(label: "Rear left", reading: state.tireRearLeft)
                tireCell(label: "Rear right", reading: state.tireRearRight)
            }
            if let front = state.recommendedFrontPSI, let rear = state.recommendedRearPSI {
                Text("Recommended cold: \(Int(front)) PSI front · \(Int(rear)) PSI rear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pressures are read live from the car over Bluetooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tireCell(label: String, reading: TireReading) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "circle.dotted")
                .font(.title2)
                .foregroundStyle(reading.hasWarning ? .red : .primary)
            Text(reading.psi.map { String(format: "%.1f PSI", $0) } ?? "—")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(reading.hasWarning ? .red : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if reading.hasWarning {
                Text("Check tire")
                    .font(.caption2).bold()
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
