import SwiftUI

/// Settings: mode (demo / live), units, swappable panels, pairing, and
/// the honest limits of the Bluetooth approach.
struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showUnpairConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                unitsSection
                panelsSection
                vehicleSection
                connectionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Unpair this Tesla?", isPresented: $showUnpairConfirm) {
                Button("Unpair", role: .destructive) {
                    Task { await viewModel.unpair() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the phone key from the Keychain. You'll need to pair again (and tap the key card) to reconnect.")
            }
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: Binding(
                get: { viewModel.mode },
                set: { newMode in Task { await viewModel.switchToMode(newMode) } }
            )) {
                Text("Demo (simulated)").tag(DashboardViewModel.AppMode.demo)
                Text("My Tesla (Bluetooth)").tag(DashboardViewModel.AppMode.live)
            }
            .pickerStyle(.segmented)
            Text(viewModel.mode == .demo
                 ? "Demo simulates a drive — works in the simulator and without the car."
                 : "Live mode talks to your Tesla directly over Bluetooth.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section("Units") {
            Toggle("Metric (km/h, °C)", isOn: $viewModel.useMetricUnits)
        }
    }

    // MARK: - Panels

    private var panelsSection: some View {
        Section("Dashboard panels") {
            Picker("Left panel", selection: Binding(
                get: { viewModel.leftPanel },
                set: { viewModel.setLeftPanel($0) }
            )) {
                ForEach(PanelKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            Picker("Right panel", selection: Binding(
                get: { viewModel.rightPanel },
                set: { viewModel.setRightPanel($0) }
            )) {
                ForEach(PanelKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
        }
    }

    // MARK: - Vehicle

    private var vehicleSection: some View {
        Section("Vehicle") {
            if viewModel.isPaired {
                LabeledContent("Paired VIN", value: viewModel.vin)
                    .font(.system(.body, design: .monospaced))
                Button("Unpair this Tesla", role: .destructive) {
                    showUnpairConfirm = true
                }
            } else {
                Text("No Tesla paired yet.")
                Button("Pair my Tesla") {
                    Task { await viewModel.switchToMode(.live) }
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Status", value: viewModel.connection.label)
            if viewModel.mode == .live {
                Button("Reconnect") {
                    Task { await viewModel.reconnect() }
                }
                .disabled(viewModel.connection.isConnected)
            }
            if let firmware = viewModel.vehicleState.firmwareVersion {
                LabeledContent("Car software", value: firmware)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0 (1)")
            Text("TeslaDash talks to your car directly over Bluetooth LE using Tesla's published vehicle-command protocol. No Tesla account, no cloud, no Fleet API. Your phone key lives in the iOS Keychain and never leaves the device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Limits: Bluetooth range is ~10 m — the phone must be in or near the car. No remote access. Infotainment data (drive, charge, climate, media) needs the car awake; the app wakes it automatically. Pre-2021 Model S/X don't support Bluetooth phone keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
