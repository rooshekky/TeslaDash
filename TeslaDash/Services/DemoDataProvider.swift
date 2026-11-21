import CoreLocation
import Foundation

/// Simulated live data so the whole app works in the iOS simulator and
/// without the car nearby. CoreBluetooth does not work in the simulator,
/// so demo mode is a first-class feature, not a fallback.
///
/// The simulation cycles: parked → driving around Los Angeles → charging.
/// Speed, battery drain/charge, odometer, and GPS position all move
/// together so the dashboard, map, and trip logger behave realistically.
@MainActor
final class DemoDataProvider: VehicleDataProvider {
    let isDemo = true

    let stateStream: AsyncStream<VehicleState>
    let connectionStream: AsyncStream<ProviderConnectionState>
    private let stateContinuation: AsyncStream<VehicleState>.Continuation
    private let connectionContinuation: AsyncStream<ProviderConnectionState>.Continuation

    private var tickTask: Task<Void, Never>?
    private var state: VehicleState
    private var batteryFraction: Double = 72
    private var phase: Phase = .parked
    private var phaseElapsed: TimeInterval = 0
    private var headingDegrees: Double = 45
    private var latitude: Double = 34.0522 // Downtown Los Angeles
    private var longitude: Double = -118.2437

    private enum Phase {
        case parked
        case driving
        case charging
    }

    init() {
        state = VehicleState(
            speedMph: 0,
            gear: .park,
            powerKW: 0,
            odometerMiles: 12_483.7,
            batteryPercent: 72,
            ratedRangeMiles: 218,
            estimatedRangeMiles: 205,
            chargingStatus: .disconnected,
            chargerPowerKW: 0,
            minutesToFull: nil,
            chargeLimitPercent: 80,
            locked: true,
            insideTempCelsius: 21.5,
            outsideTempCelsius: 24.0,
            climateOn: true,
            driverTempCelsius: 21.0,
            tireFrontLeft: TireReading(psi: 42.1),
            tireFrontRight: TireReading(psi: 41.8),
            tireRearLeft: TireReading(psi: 42.4),
            tireRearRight: TireReading(psi: 42.0),
            recommendedFrontPSI: 42,
            recommendedRearPSI: 42,
            mediaArtist: "Demo Artist",
            mediaTitle: "Midnight Drive (Demo Mix)",
            mediaAlbum: "Demo Tapes",
            mediaSource: "Bluetooth",
            mediaVolumeFraction: 0.6,
            firmwareVersion: "2026.8.3 (demo)"
        )
        state.latitude = latitude
        state.longitude = longitude
        state.headingDegrees = headingDegrees

        let (sStream, sCont) = AsyncStream.makeStream(of: VehicleState.self)
        let (cStream, cCont) = AsyncStream.makeStream(of: ProviderConnectionState.self)
        stateStream = sStream
        connectionStream = cStream
        stateContinuation = sCont
        connectionContinuation = cCont
    }

    func connect() async throws {
        connectionContinuation.yield(.connected)
        stateContinuation.yield(state)
        tickTask = Task {
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func disconnect() async {
        tickTask?.cancel()
        tickTask = nil
        connectionContinuation.yield(.disconnected)
        stateContinuation.finish()
        connectionContinuation.finish()
    }

    func send(_ command: AppCommand) async throws {
        switch command {
        case .lock: state.locked = true
        case .unlock: state.locked = false
        case .wake: state.carAwake = true
        case .climateOn: state.climateOn = true
        case .climateOff: state.climateOn = false
        case .chargeStart:
            state.chargingStatus = .charging
            phase = .charging
            phaseElapsed = 0
        case .chargeStop:
            state.chargingStatus = .disconnected
            phase = .parked
            phaseElapsed = 0
        case let .setChargeLimit(percent):
            state.chargeLimitPercent = percent
        case .mediaNext:
            state.mediaTitle = "Next Track (Demo Mix)"
        case .mediaPrevious:
            state.mediaTitle = "Previous Track (Demo Mix)"
        case .mediaVolumeUp:
            state.mediaVolumeFraction = min(1, (state.mediaVolumeFraction ?? 0.5) + 0.05)
        case .mediaVolumeDown:
            state.mediaVolumeFraction = max(0, (state.mediaVolumeFraction ?? 0.5) - 0.05)
        case .honk, .flashLights, .openTrunk, .openFrunk, .mediaToggle,
             .setTemperature:
            break
        }
        state.lastUpdated = Date()
        stateContinuation.yield(state)
    }

    // MARK: - Simulation

    private func tick() {
        phaseElapsed += 0.5

        switch phase {
        case .parked:
            state.speedMph = 0
            state.gear = .park
            state.powerKW = 0
            state.locked = true
            state.chargingStatus = .disconnected
            if phaseElapsed > 6 {
                phase = .driving
                phaseElapsed = 0
            }

        case .driving:
            // Smooth speed profile: accelerate, cruise ~45–65 mph, slow down.
            let t = phaseElapsed
            let target: Double = {
                if t < 8 { return 25 + t * 4 } // accelerate
                if t < 45 { return 52 + sin(t / 4) * 10 } // cruise with variation
                if t < 55 { return max(0, 55 - (t - 45) * 6) } // decelerate
                return 0
            }()
            state.speedMph = target
            state.gear = target > 0.5 ? .drive : .park
            state.powerKW = Int(target * 0.45) - (target < 5 ? 8 : 0)
            state.locked = false
            state.isUserPresent = true
            batteryFraction = max(5, batteryFraction - 0.004)
            state.batteryPercent = Int(batteryFraction)
            state.ratedRangeMiles = max(0, state.ratedRangeMiles - 0.012)
            state.odometerMiles += target / 3600 * 0.5
            advancePosition(speedMph: target)
            if phaseElapsed > 55 {
                phase = .charging
                phaseElapsed = 0
            }

        case .charging:
            state.speedMph = 0
            state.gear = .park
            state.powerKW = 0
            state.locked = true
            state.chargingStatus = .charging
            state.chargerPowerKW = 11
            state.chargerVoltage = 240
            state.chargerCurrent = 48
            state.chargePortOpen = true
            batteryFraction = min(Double(state.chargeLimitPercent), batteryFraction + 0.05)
            state.batteryPercent = Int(batteryFraction)
            state.minutesToFull = Int((Double(state.chargeLimitPercent) - batteryFraction) * 2.2)
            if batteryFraction >= Double(state.chargeLimitPercent) || phaseElapsed > 30 {
                state.chargingStatus = .complete
                state.chargerPowerKW = 0
                state.chargePortOpen = false
                phase = .parked
                phaseElapsed = 0
            }
        }

        // Small tire-pressure wobble so the panel feels alive.
        state.tireFrontLeft.psi = 42.1 + sin(phaseElapsed / 9) * 0.2
        state.tireFrontRight.psi = 41.8 + cos(phaseElapsed / 11) * 0.2
        state.tireRearLeft.psi = 42.4 + sin(phaseElapsed / 13) * 0.2
        state.tireRearRight.psi = 42.0 + cos(phaseElapsed / 7) * 0.2

        state.latitude = latitude
        state.longitude = longitude
        state.headingDegrees = headingDegrees
        state.lastUpdated = Date()
        stateContinuation.yield(state)
    }

    private func advancePosition(speedMph: Double) {
        // Move along the current heading; gentle heading drift for curves.
        headingDegrees += sin(phaseElapsed / 20) * 0.6
        let miles = speedMph / 3600 * 0.5
        let radians = headingDegrees * .pi / 180
        latitude += miles / 69 * cos(radians)
        longitude += miles / 54.6 * sin(radians)
    }
}
