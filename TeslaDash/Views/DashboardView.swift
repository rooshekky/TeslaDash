import MapKit
import SwiftUI

/// Main dashboard. Portrait shows the full dashboard; rotating to
/// landscape switches to the instrument-cluster layout.
struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    ClusterView(viewModel: viewModel)
                } else {
                    PortraitDashboard(viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Portrait dashboard

private struct PortraitDashboard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var state: VehicleState { viewModel.vehicleState }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusRow
                speedBlock
                batteryBlock
                quickActions
                panelsRow
            }
            .padding()
        }
        .navigationTitle("TeslaDash")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Status

    private var statusRow: some View {
        HStack {
            Label(viewModel.connection.label, systemImage: connectionIcon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(connectionColor.opacity(0.15), in: Capsule())
                .foregroundStyle(connectionColor)
            Spacer()
            if viewModel.mode == .demo {
                Label("DEMO", systemImage: "play.circle")
                    .font(.caption).bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if !state.carAwake {
                Label("Car asleep", systemImage: "moon.zzz")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private var connectionIcon: String {
        viewModel.connection.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
    }

    private var connectionColor: Color {
        viewModel.connection.isConnected ? .green : .orange
    }

    // MARK: Speed

    private var speedBlock: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(speedText)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(viewModel.useMetricUnits ? "km/h" : "mph")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                gearChip
                Label("\(state.powerKW) kW", systemImage: state.powerKW < 0 ? "bolt.braking" : "bolt.fill")
                    .font(.subheadline)
                Label("\(Int(state.odometerMiles)) mi", systemImage: "gauge.with.dots.needle.0percent")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var speedText: String {
        let speed = viewModel.useMetricUnits ? state.speedMph * 1.60934 : state.speedMph
        return String(Int(speed.rounded()))
    }

    private var gearChip: some View {
        Text(state.gear.label)
            .font(.title2).bold()
            .frame(width: 44, height: 44)
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

    // MARK: Battery

    private var batteryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(state.batteryPercent)%", systemImage: "battery.75")
                    .font(.headline)
                Spacer()
                Text("\(Int(state.estimatedRangeMiles)) mi est · \(Int(state.ratedRangeMiles)) mi rated")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(state.batteryPercent), total: 100)
                .tint(batteryColor)
            if state.chargingStatus != .disconnected {
                HStack {
                    Text(state.chargingStatus.label)
                    Spacer()
                    if state.chargerPowerKW > 0 {
                        Text("\(state.chargerPowerKW) kW")
                    }
                    if let minutes = state.minutesToFull {
                        Text("\(minutes) min to full")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var batteryColor: Color {
        switch state.batteryPercent {
        case ..<20: .red
        case ..<50: .orange
        default: .green
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionButton(
                title: state.locked ? "Unlock" : "Lock",
                icon: state.locked ? "lock.open" : "lock",
                command: state.locked ? .unlock : .lock
            )
            actionButton(title: "Honk", icon: "speaker.wave.3", command: .honk)
            actionButton(title: "Flash", icon: "lightbulb", command: .flashLights)
            actionButton(
                title: state.climateOn ? "Climate off" : "Climate on",
                icon: "fanblades",
                command: state.climateOn ? .climateOff : .climateOn
            )
            actionButton(title: "Trunk", icon: "car.rear", command: .openTrunk)
        }
    }

    private func actionButton(title: String, icon: String, command: AppCommand) -> some View {
        Button {
            Task { await viewModel.sendCommand(command) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.connection.isConnected && viewModel.mode == .live)
    }

    // MARK: Panels

    private var panelsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            PanelCard(kind: viewModel.leftPanel, viewModel: viewModel)
            PanelCard(kind: viewModel.rightPanel, viewModel: viewModel)
        }
    }
}

// MARK: - Swappable panel card

struct PanelCard: View {
    let kind: PanelKind
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.headline)
            PanelContentView(kind: kind, viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Renders the body of one swappable side panel.
struct PanelContentView: View {
    let kind: PanelKind
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        switch kind {
        case .map:
            MiniMapView(viewModel: viewModel)
        case .navigation:
            NavigationPanelView(viewModel: viewModel)
        case .music:
            MediaPanelView(viewModel: viewModel)
        case .tirePressure:
            TirePressureView(viewModel: viewModel)
        case .climate:
            ClimatePanelView(viewModel: viewModel)
        }
    }
}

// MARK: - Mini map (panel)

private struct MiniMapView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        if let coord = viewModel.mapCoordinate {
            Map(position: .constant(.region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )))) {
                if let route = viewModel.route {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 3)
                }
                UserAnnotation()
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(true)
        } else {
            Label("Waiting for GPS…", systemImage: "location.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(height: 180)
        }
    }
}

// MARK: - Navigation panel

private struct NavigationPanelView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        if let route = viewModel.route {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.destinationName ?? "Destination")
                    .font(.headline)
                Text("ETA \(viewModel.routeETA ?? "—") · \(Int(route.distance / 1609.34)) mi")
                    .font(.subheadline)
                if let arrival = viewModel.batteryOnArrivalPercent {
                    Text("Battery on arrival: ~\(arrival)% (est.)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("End navigation") { viewModel.clearRoute() }
                    .font(.subheadline)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active route")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Search a destination on the Map tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Climate panel

private struct ClimatePanelView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var targetTempCelsius: Double = 21

    private var state: VehicleState { viewModel.vehicleState }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Inside", systemImage: "thermometer.medium")
                Spacer()
                Text(tempString(state.insideTempCelsius))
                    .font(.headline)
            }
            HStack {
                Label("Outside", systemImage: "thermometer.sun")
                Spacer()
                Text(tempString(state.outsideTempCelsius))
                    .font(.headline)
            }
            HStack {
                Text("Set temperature")
                Spacer()
                Button { adjustTemp(by: -0.5) } label: {
                    Image(systemName: "minus.circle.fill")
                }
                Text(tempString(targetTempCelsius))
                    .font(.headline)
                    .frame(minWidth: 52)
                Button { adjustTemp(by: 0.5) } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            HStack {
                Text(state.climateOn ? "Climate on" : "Climate off")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(state.climateOn ? "Turn off" : "Turn on") {
                    Task { await viewModel.sendCommand(state.climateOn ? .climateOff : .climateOn) }
                }
                .font(.subheadline)
            }
        }
        .font(.subheadline)
        .onAppear {
            if let setpoint = state.driverTempCelsius {
                targetTempCelsius = setpoint
            }
        }
    }

    private func adjustTemp(by delta: Double) {
        targetTempCelsius = min(28, max(16, targetTempCelsius + delta))
        let temp = targetTempCelsius
        Task {
            await viewModel.sendCommand(.setTemperature(driverCelsius: temp, passengerCelsius: temp))
        }
    }

    private func tempString(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        if viewModel.useMetricUnits {
            return String(format: "%.1f °C", celsius)
        }
        return String(format: "%.0f °F", celsius * 9 / 5 + 32)
    }
}
