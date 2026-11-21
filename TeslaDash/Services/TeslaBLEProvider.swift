import Foundation
import TeslaBLE

/// Live vehicle data over Bluetooth LE, using the `swift-tesla-ble`
/// package (pure-Swift reimplementation of Tesla's published
/// vehicle-command BLE protocol). No cloud, no Tesla account, no Fleet API.
///
/// Polling strategy (BLE is request/response, not a push stream):
/// - Drive state (`fetchDrive()`) every ~500 ms while driving — the
///   low-latency fast path for speed/gear.
/// - Full snapshot (`fetch(.all)`) every 5 s for battery, charge, climate,
///   closures, tires, media.
/// - VCSEC body-controller query on connect to detect a sleeping car;
///   infotainment data is only available while the car is awake, so a
///   sleeping car is woken with `.security(.wakeVehicle)` first.
@MainActor
final class TeslaBLEProvider: VehicleDataProvider {
    let isDemo = false
    let vin: String

    let stateStream: AsyncStream<VehicleState>
    let connectionStream: AsyncStream<ProviderConnectionState>
    private let stateContinuation: AsyncStream<VehicleState>.Continuation
    private let connectionContinuation: AsyncStream<ProviderConnectionState>.Continuation

    private var client: TeslaVehicleClient?
    private var drivePollTask: Task<Void, Never>?
    private var fullPollTask: Task<Void, Never>?
    private var stateObserveTask: Task<Void, Never>?
    private var currentState = VehicleState()
    private var lastWakeAttempt = Date.distantPast

    init(vin: String) {
        self.vin = vin
        let (sStream, sCont) = AsyncStream.makeStream(of: VehicleState.self)
        let (cStream, cCont) = AsyncStream.makeStream(of: ProviderConnectionState.self)
        stateStream = sStream
        connectionStream = cStream
        stateContinuation = sCont
        connectionContinuation = cCont
    }

    // MARK: - Lifecycle

    func connect() async throws {
        guard client == nil else { return }
        connectionContinuation.yield(.scanning)

        let keyStore = KeychainTeslaKeyStore(service: "com.tesladash.app")
        let client = TeslaVehicleClient(
            vin: vin,
            keyStore: keyStore,
            logger: OSLogTeslaBLELogger(subsystem: "com.tesladash.app")
        )
        self.client = client

        stateObserveTask = Task {
            for await state in client.stateStream {
                guard !Task.isCancelled else { break }
                connectionContinuation.yield(Self.mapConnectionState(state))
            }
        }

        do {
            try await client.connect()
        } catch {
            // Tear down quietly and report the failure once — calling
            // disconnect() here would yield `.disconnected` and then
            // `.failed`, flashing the wrong state in the UI.
            await tearDownSilently()
            connectionContinuation.yield(.failed(error.localizedDescription))
            stateContinuation.finish()
            connectionContinuation.finish()
            throw error
        }

        await ensureAwake(client: client)
        startPolling(client: client)
    }

    func disconnect() async {
        await tearDownSilently()
        connectionContinuation.yield(.disconnected)
        stateContinuation.finish()
        connectionContinuation.finish()
    }

    /// Cancels polling and drops the client without touching the
    /// connection stream. `disconnect()` and the `connect()` failure path
    /// build on this.
    private func tearDownSilently() async {
        drivePollTask?.cancel()
        fullPollTask?.cancel()
        stateObserveTask?.cancel()
        drivePollTask = nil
        fullPollTask = nil
        stateObserveTask = nil
        if let client {
            await client.disconnect()
        }
        client = nil
    }

    // MARK: - Commands

    func send(_ command: AppCommand) async throws {
        guard let client else { throw TeslaBLEError.notConnected }
        let teslaCommand: Command = switch command {
        case .lock: .security(.lock)
        case .unlock: .security(.unlock)
        case .wake: .security(.wakeVehicle)
        case .honk: .actions(.honk)
        case .flashLights: .actions(.flashLights)
        case .openTrunk: .security(.openTrunk)
        case .openFrunk: .security(.openFrunk)
        case .climateOn: .climate(.on)
        case .climateOff: .climate(.off)
        case let .setTemperature(driver, passenger):
            .climate(.setTemperature(driver: Float(driver), passenger: Float(passenger)))
        case .chargeStart: .charge(.start)
        case .chargeStop: .charge(.stop)
        case let .setChargeLimit(percent): .charge(.setLimit(percent: Int32(percent)))
        case .mediaToggle: .media(.togglePlayback)
        case .mediaNext: .media(.nextTrack)
        case .mediaPrevious: .media(.previousTrack)
        case .mediaVolumeUp: .media(.volumeUp)
        case .mediaVolumeDown: .media(.volumeDown)
        }
        try await client.send(teslaCommand)
    }

    // MARK: - Wake handling

    /// VCSEC answers even while Infotainment is asleep, so the sleep status
    /// query is the reliable way to know whether a wake is needed.
    private func ensureAwake(client: TeslaVehicleClient) async {
        do {
            let result = try await client.query(.bodyControllerState)
            if case .bodyControllerState(let status) = result,
               status.vehicleSleepStatus == .vehicleSleepStatusAsleep {
                currentState.carAwake = false
                publish()
                try? await client.send(.security(.wakeVehicle))
                try? await Task.sleep(for: .seconds(8))
                currentState.carAwake = true
                publish()
            }
        } catch {
            // Best effort only — polling will surface a real problem.
        }
    }

    private func handleFetchFailure(client: TeslaVehicleClient) async {
        // Rate-limit wakes: at most one attempt every 30 seconds.
        guard Date().timeIntervalSince(lastWakeAttempt) > 30 else { return }
        lastWakeAttempt = Date()
        currentState.carAwake = false
        publish()
        try? await client.send(.security(.wakeVehicle))
        try? await Task.sleep(for: .seconds(10))
        currentState.carAwake = true
        publish()
    }

    // MARK: - Polling

    private func startPolling(client: TeslaVehicleClient) {
        drivePollTask = Task {
            while !Task.isCancelled {
                do {
                    let drive = try await client.fetchDrive()
                    applyDrive(drive)
                } catch {
                    if Task.isCancelled { break }
                    // Fire-and-forget: the wake takes ~10 s, and blocking
                    // this loop on it would freeze speed updates.
                    Task { await handleFetchFailure(client: client) }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        fullPollTask = Task {
            while !Task.isCancelled {
                do {
                    let snapshot = try await client.fetch(.all)
                    applySnapshot(snapshot)
                } catch {
                    if Task.isCancelled { break }
                    Task { await handleFetchFailure(client: client) }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Mapping (library types -> app types)

    private func applyDrive(_ drive: DriveState) {
        if let speed = drive.speedMph { currentState.speedMph = speed }
        if let gear = drive.shiftState {
            currentState.gear = switch gear {
            case .park: .park
            case .reverse: .reverse
            case .neutral: .neutral
            case .drive: .drive
            }
        }
        if let power = drive.powerKW { currentState.powerKW = power }
        if let odo = drive.odometerHundredthsMile {
            currentState.odometerMiles = Double(odo) / 100
        }
        currentState.lastUpdated = Date()
        publish()
    }

    private func applySnapshot(_ snapshot: TeslaVehicleSnapshot) {
        if let charge = snapshot.charge {
            if let level = charge.batteryLevel { currentState.batteryPercent = level }
            if let range = charge.batteryRangeMiles { currentState.ratedRangeMiles = range }
            if let est = charge.estBatteryRangeMiles { currentState.estimatedRangeMiles = est }
            if let status = charge.chargingStatus {
                currentState.chargingStatus = switch status {
                case .disconnected: .disconnected
                case .charging: .charging
                case .complete: .complete
                case .stopped: .stopped
                case .starting: .starting
                }
            }
            if let kw = charge.chargerPower { currentState.chargerPowerKW = kw }
            if let volts = charge.chargerVoltage { currentState.chargerVoltage = volts }
            if let amps = charge.chargerCurrent { currentState.chargerCurrent = amps }
            if let minutes = charge.minutesToFullCharge { currentState.minutesToFull = minutes }
            if let limit = charge.chargeLimitPercent { currentState.chargeLimitPercent = limit }
            if let open = charge.chargePortOpen { currentState.chargePortOpen = open }
        }
        if let climate = snapshot.climate {
            currentState.insideTempCelsius = climate.insideTempCelsius
            currentState.outsideTempCelsius = climate.outsideTempCelsius
            if let on = climate.isClimateOn { currentState.climateOn = on }
            currentState.driverTempCelsius = climate.driverTempSettingCelsius
        }
        if let closures = snapshot.closures {
            if let locked = closures.locked { currentState.locked = locked }
            if let v = closures.frontDriverDoor { currentState.frontLeftDoorOpen = v }
            if let v = closures.frontPassengerDoor { currentState.frontRightDoorOpen = v }
            if let v = closures.rearDriverDoor { currentState.rearLeftDoorOpen = v }
            if let v = closures.rearPassengerDoor { currentState.rearRightDoorOpen = v }
            if let v = closures.frontTrunk { currentState.frunkOpen = v }
            if let v = closures.rearTrunk { currentState.trunkOpen = v }
            if let v = closures.sentryModeActive { currentState.sentryMode = v }
            if let v = closures.isUserPresent { currentState.isUserPresent = v }
        }
        if let tires = snapshot.tirePressure {
            currentState.tireFrontLeft = Self.tireReading(tires.frontLeft)
            currentState.tireFrontRight = Self.tireReading(tires.frontRight)
            currentState.tireRearLeft = Self.tireReading(tires.rearLeft)
            currentState.tireRearRight = Self.tireReading(tires.rearRight)
            if let rec = tires.recommendedColdFrontBar {
                currentState.recommendedFrontPSI = rec * 14.5038
            }
            if let rec = tires.recommendedColdRearBar {
                currentState.recommendedRearPSI = rec * 14.5038
            }
        }
        if let media = snapshot.media {
            currentState.mediaArtist = media.nowPlayingArtist
            currentState.mediaTitle = media.nowPlayingTitle
            if let detail = snapshot.mediaDetail {
                currentState.mediaAlbum = detail.nowPlayingAlbum
                currentState.mediaSource = detail.nowPlayingSource
            }
            if let vol = media.audioVolume, let max = media.audioVolumeMax, max > 0 {
                currentState.mediaVolumeFraction = vol / max
            }
        }
        if let drive = snapshot.drive { applyDrive(drive) }
        if let sw = snapshot.softwareUpdate { currentState.firmwareVersion = sw.version }
        currentState.lastUpdated = Date()
        publish()
    }

    private static func tireReading(_ tire: TirePressureState.Tire?) -> TireReading {
        guard let tire else { return TireReading() }
        return TireReading(
            psi: tire.pressureBar.map { $0 * 14.5038 },
            hasWarning: tire.hasWarning ?? false
        )
    }

    private static func mapConnectionState(_ state: ConnectionState) -> ProviderConnectionState {
        switch state {
        case .disconnected: .disconnected
        case .scanning: .scanning
        case .connecting: .connecting
        case .handshaking: .handshaking
        case .connected: .connected
        }
    }

    private func publish() {
        stateContinuation.yield(currentState)
    }
}
