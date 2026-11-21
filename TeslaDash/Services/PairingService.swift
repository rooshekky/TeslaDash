import CryptoKit
import Foundation
import TeslaBLE

/// First-time Bluetooth key pairing.
///
/// Flow (matches the swift-tesla-ble demo and Tesla's own pairing model):
/// 1. Generate a P-256 keypair and store the private key in the iOS
///    Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — device-only,
///    never synced or backed up).
/// 2. Connect in `.pairing` mode (scan + BLE connect, no session handshake).
/// 3. Send the unsigned `addKey` request (role `.owner`, form factor
///    `.iosDevice`). The car then waits for the owner to tap an existing
///    owner key card on the center console.
/// 4. Reconnect in normal mode until the signed handshake succeeds —
///    that proves the key is active.
///
/// No Tesla account, no cloud, no Fleet API anywhere in this flow.
@MainActor
final class PairingService: ObservableObject {
    enum Step: Equatable {
        case idle
        case generatingKey
        case connecting
        case waitingForKeyCardTap
        case verifying
        case done
        case failed(String)

        var title: String {
            switch self {
            case .idle: "Ready to pair"
            case .generatingKey: "Creating your phone key…"
            case .connecting: "Finding your Tesla…"
            case .waitingForKeyCardTap: "Tap your key card"
            case .verifying: "Verifying the new key…"
            case .done: "Paired!"
            case .failed: "Pairing failed"
            }
        }
    }

    @Published var step: Step = .idle
    @Published var vin: String = ""

    private let keyStoreService = "com.tesladash.app"
    private var client: TeslaVehicleClient?

    /// Runs the full pairing flow for the given VIN.
    func pair(vin rawVIN: String) async {
        let vin = rawVIN.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.isValidVIN(vin) else {
            step = .failed("Enter a valid 17-character VIN (no I, O, or Q).")
            return
        }
        self.vin = vin

        // 1. Load or generate the P-256 keypair for this VIN.
        step = .generatingKey
        let keyStore = KeychainTeslaKeyStore(service: keyStoreService)
        do {
            if try keyStore.loadPrivateKey(forVIN: vin) == nil {
                let key = KeyPairFactory.generateKeyPair()
                try keyStore.savePrivateKey(key, forVIN: vin)
            }
        } catch {
            step = .failed("Could not save the phone key: \(error.localizedDescription)")
            return
        }
        let privateKey: P256.KeyAgreement.PrivateKey
        do {
            guard let key = try keyStore.loadPrivateKey(forVIN: vin) else {
                step = .failed("Could not load the phone key from the Keychain.")
                return
            }
            privateKey = key
        } catch {
            step = .failed("Could not load the phone key from the Keychain.")
            return
        }
        let publicKey = KeyPairFactory.publicKeyBytes(of: privateKey)

        // 2. Connect in pairing mode (no handshake yet).
        let client = TeslaVehicleClient(
            vin: vin,
            keyStore: keyStore,
            logger: OSLogTeslaBLELogger(subsystem: "com.tesladash.app")
        )
        self.client = client
        step = .connecting
        do {
            try await client.connect(mode: .pairing)
            // 3. Unsigned addKey request — the car now waits for the tap.
            try await client.send(.security(.addKey(
                publicKey: publicKey,
                role: .owner,
                formFactor: .iosDevice
            )))
        } catch {
            await client.disconnect()
            step = .failed("Pairing request failed: \(error.localizedDescription)")
            return
        }

        // 4. Owner taps an existing owner key card on the center console,
        //    then we verify by reconnecting in normal mode.
        step = .waitingForKeyCardTap
        await client.disconnect()
        step = .verifying
        let deadline = Date().addingTimeInterval(120)
        var verified = false
        while Date() < deadline && !verified {
            try? await Task.sleep(for: .seconds(5))
            do {
                // Short timeout per attempt so the 120 s deadline is
                // actually respected (the library default is 30 s).
                try await client.connect(timeout: .seconds(10))
                // Infotainment may be asleep on first connect — wake, then retry.
                if (try? await client.fetchDrive()) == nil {
                    try? await client.send(.security(.wakeVehicle))
                    try? await Task.sleep(for: .seconds(8))
                    let _ = try await client.fetchDrive()
                }
                verified = true
            } catch {
                await client.disconnect()
            }
        }
        await client.disconnect()

        if verified {
            step = .done
            UserDefaults.standard.set(vin, forKey: "pairedVIN")
        } else {
            step = .failed(
                "Timed out waiting for the key-card tap. Make sure you tapped an " +
                "existing owner key card on the center console, then try again."
            )
        }
    }

    func reset() {
        step = .idle
    }

    /// VINs are 17 characters, alphanumeric, excluding I, O, Q.
    static func isValidVIN(_ vin: String) -> Bool {
        guard vin.count == 17 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
        return vin.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
