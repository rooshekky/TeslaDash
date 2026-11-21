import SwiftUI

/// First-time Bluetooth pairing.
///
/// The user enters the 17-character VIN, the app creates a P-256 phone
/// key, and the car authorizes it when the owner taps an existing owner
/// key card on the center console. No Tesla account, no cloud.
struct PairingView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var pairing: PairingService
    @State private var vinText = ""

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        self._pairing = ObservedObject(wrappedValue: viewModel.pairingService)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    vinSection
                    stepSection
                    actions
                }
                .padding()
            }
            .navigationTitle("Pair your Tesla")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect over Bluetooth")
                .font(.title2).bold()
            Text("Your phone talks directly to your car — no Tesla account, no cloud, nothing leaves the phone. You only do this once.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var vinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vehicle VIN")
                .font(.headline)
            TextField("5YJ3E1EA… (17 characters)", text: $vinText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            Text("Find it on the driver's door jamb, the windshield plate, or in the Tesla app under Controls → Software.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepSection: some View {
        switch pairing.step {
        case .idle:
            EmptyView()
        case .generatingKey:
            Label("Creating your phone key…", systemImage: "key.fill")
        case .connecting:
            Label("Finding your Tesla over Bluetooth…", systemImage: "antenna.radiowaves.left.and.right")
        case .waitingForKeyCardTap, .verifying:
            VStack(alignment: .leading, spacing: 12) {
                Label("Tap your key card now", systemImage: "creditcard")
                    .font(.headline)
                Text("Hold an existing owner key card (or key fob) on the center console, just below the screen. The car will ask you to confirm the new phone key — tap Confirm on the touchscreen.")
                Text("The app is listening for the car to accept the key. This can take up to 2 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                Label("Paired!", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Your phone is now a key for this Tesla. The dashboard will connect automatically whenever you're in the car.")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Pairing failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if pairing.step == .done {
                Button("Start driving") {
                    viewModel.refreshPairedState()
                    Task { await viewModel.switchToMode(.live) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if pairing.step == .idle || isFailed {
                Button("Pair with my Tesla") {
                    Task { await pairing.pair(vin: vinText) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vinText.trimmingCharacters(in: .whitespaces).count < 17)
            }

            Button("Try demo mode instead") {
                Task { await viewModel.switchToMode(.demo) }
            }
            .buttonStyle(.bordered)

            Text("Demo mode simulates a drive — no car needed. You can pair later from Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var isFailed: Bool {
        if case .failed = pairing.step { return true }
        return false
    }
}
