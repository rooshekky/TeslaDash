import SwiftUI

/// Landscape instrument-cluster layout — the phone mounted behind the
/// steering wheel, Dashla-style. Big speed in the middle, battery and
/// range on the left, power and charging on the right.
struct ClusterView: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var state: VehicleState { viewModel.vehicleState }

    var body: some View {
        HStack(spacing: 24) {
            leftColumn
            centerSpeed
            rightColumn
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(Color.black)
        .foregroundStyle(.white)
    }

    // MARK: Left — battery & range

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(state.batteryPercent)%", systemImage: "battery.75")
                .font(.system(size: 34, weight: .bold))
            Text("\(Int(state.estimatedRangeMiles)) mi")
                .font(.title2)
                .foregroundStyle(.secondary)
            gearChip
            if state.chargingStatus != .disconnected {
                Text(state.chargingStatus.label)
                    .font(.headline)
                    .foregroundStyle(.green)
                if state.chargerPowerKW > 0 {
                    Text("\(state.chargerPowerKW) kW")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label(viewModel.connection.label, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Center — speed

    private var centerSpeed: some View {
        VStack(spacing: 2) {
            Text(speedText)
                .font(.system(size: 150, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(viewModel.useMetricUnits ? "km/h" : "mph")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("\(state.powerKW) kW")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var speedText: String {
        let speed = viewModel.useMetricUnits ? state.speedMph * 1.60934 : state.speedMph
        return String(Int(speed.rounded()))
    }

    // MARK: Right — climate & tires

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let inside = state.insideTempCelsius {
                Label(tempString(inside), systemImage: "thermometer.medium")
                    .font(.title2)
            }
            if let outside = state.outsideTempCelsius {
                Text("Outside \(tempString(outside))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                tireMini(label: "FL", reading: state.tireFrontLeft)
                tireMini(label: "FR", reading: state.tireFrontRight)
                tireMini(label: "RL", reading: state.tireRearLeft)
                tireMini(label: "RR", reading: state.tireRearRight)
            }
            Spacer()
            if let title = state.mediaTitle {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(title)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    if let artist = state.mediaArtist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func tireMini(label: String, reading: TireReading) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(reading.psi.map { String(format: "%.0f", $0) } ?? "—")
                .font(.headline)
                .foregroundStyle(reading.hasWarning ? .red : .white)
        }
    }

    private var gearChip: some View {
        Text(state.gear.label)
            .font(.title).bold()
            .frame(width: 52, height: 52)
            .background(gearColor, in: Circle())
            .foregroundStyle(.white)
    }

    private var gearColor: Color {
        switch state.gear {
        case .park: .gray
        case .reverse: .orange
        case .neutral: .yellow
        case .drive: .green
        }
    }

    private func tempString(_ celsius: Double) -> String {
        if viewModel.useMetricUnits {
            return String(format: "%.1f °C", celsius)
        }
        return String(format: "%.0f °F", celsius * 9 / 5 + 32)
    }
}
