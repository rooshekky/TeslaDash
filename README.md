# TeslaDash — a Dashla-style Tesla dashboard for iOS

Turn your iPhone into a live Tesla instrument cluster. **TeslaDash talks to
your car directly over Bluetooth Low Energy** — no Tesla account, no cloud,
no Fleet API, nothing leaves the phone.

Built for a **2024 Tesla Model 3 Highland** and an **iPhone 14 Plus**, but it
works with any Model 3 / Model Y and any 2021+ Model S/X.

## Features

- **Live dashboard** — big speed, gear (P/R/N/D), battery %, rated +
  estimated range, charging status + kW + time-to-full, power (kW)
- **Tire pressure** per wheel, with warnings and recommended cold pressures
- **Live map** (MapKit) with the car's position, destination search, and
  on-device routing with **ETA and battery-on-arrival** (computed on the
  phone with MapKit — the car's own navigation destination isn't used)
- **Now-playing media** panel with transport controls sent back to the car
- **Trip history** logged locally on-device (the car has no trip API — the
  app records trips itself)
- **Customizable side panels** — map / navigation / music / tire pressure /
  climate, pick left and right in Settings
- **Landscape instrument-cluster layout** — rotate the phone and the
  dashboard becomes a full-width cluster
- **Quick actions** — lock/unlock, honk, flash lights, climate, trunk
- **Demo mode** — a simulated drive (parked → driving → charging) so the
  whole app works in the iOS simulator and without the car nearby
- **Screen stays awake** while the dashboard is up

## How the data gets to your phone

Tesla published the phone-to-car Bluetooth protocol as the
[vehicle-command](https://github.com/teslamotors/vehicle-command) Go SDK.
This app uses
[swift-tesla-ble](https://github.com/shoujiaxin/swift-tesla-ble) — a
pure-Swift reimplementation of that protocol (P-256 ECDH session handshake,
AES-GCM message encryption, VCSEC + Infotainment domains) — as a Swift
Package dependency.

- Your phone generates a P-256 keypair; the private key lives in the iOS
  Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — device-only,
  never synced or backed up).
- You pair once by tapping an existing owner key card on the center
  console. After that the car trusts your phone as a key.
- The app polls drive state every ~500 ms and the full snapshot every 5 s.
  BLE is request/response, not a push stream — ~2 Hz speed updates are what
  "live" looks like over this protocol.
- If the car is asleep, the app wakes it first (VCSEC answers while asleep;
  infotainment data needs the car awake).

## Requirements

| Thing | Requirement |
|---|---|
| Car | Model 3 / Model Y (any year), Model S/X 2021+, Cybertruck, Model 3 Highland — all have the Bluetooth phone-key system. **Pre-2021 Model S/X do NOT work over Bluetooth.** |
| iPhone | iPhone 14 Plus or any iPhone running **iOS 17+**. The BLE library requires iOS 17, so this app targets iOS 17.0 (not 16). |
| To build | **Xcode 26+** (Swift 6.2 toolchain; the project uses Swift 6.0 language mode) on a Mac — or no Mac at all, see below. |
| To install | **AltStore** (free Apple ID, Windows) — primary. TestFlight later, if you ever get a paid Apple Developer account ($99/yr). |

## Install — no Mac needed (recommended)

You run Windows, so the normal route is: push this project to GitHub and
let a cloud Mac build it. The workflow always produces an unsigned `.ipa`
you install with AltStore.

### Option A — AltStore (primary, free)

No Apple Developer account needed — just a free Apple ID.

1. **Get the .ipa** — push this project to GitHub (`git push` to `main`,
   or run the workflow manually from the Actions tab). When the run
   finishes, download **`TeslaDash-unsigned.ipa`** from the run's
   Artifacts.
2. **AltServer on Windows** — install
   [AltServer](https://altstore.io) on your PC and run it. It sits in
   the system tray.
3. **AltStore on your iPhone** — connect your iPhone to the PC by USB
   the first time, then in AltServer choose Install AltStore and sign in
   with your Apple ID. AltStore appears on your phone.
4. **Install TeslaDash** — get the downloaded `.ipa` onto your phone
   (email it to yourself, or put it in iCloud Drive / Files), open it,
   and choose **Open in AltStore**. Sign in with your Apple ID when
   asked — AltStore re-signs the app with your free account.
5. **Trust the certificate** — first launch: Settings → General → VPN &
   Device Management → tap your Apple ID → Trust.
6. **Keep it refreshed** — that's it. AltStore refreshes the signature
   automatically over Wi-Fi while AltServer is running on your PC.

Honest limits of the free route:

- The app signature **expires every 7 days** and must be refreshed over
  Wi-Fi by AltServer (automatic in the background while your PC is on
  and the phone is on the same Wi-Fi).
- A free Apple ID can have **at most 3 sideloaded apps** at once, and
  AltStore itself counts as one — so TeslaDash plus one other app, max.
- If the signature lapses before a refresh, the app won't open until you
  refresh it. It does not delete your data or pairing.

### Later: upgrade to TestFlight (needs a paid Developer account)

If you ever get an Apple Developer account ($99/year), you can switch to
TestFlight — no weekly refresh, no 3-app limit, new builds install
automatically:

1. Enroll at [developer.apple.com](https://developer.apple.com).
2. Create an App Store Connect API key (App Manager role) and save the
   Key ID, Issuer ID, and the `.p8` file.
3. Create an "Apple Distribution" certificate, export it as `.p12`
   (with a password), and base64-encode it.
4. Create an App Store provisioning profile for App ID
   `com.tesladash.app`, download the `.mobileprovision`, base64-encode it.
5. Add all eight secrets to the GitHub repo (Settings → Secrets and
   variables → Actions): `APP_STORE_CONNECT_API_KEY_ID`,
   `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`,
   `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
   `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`,
   `APPLE_TEAM_ID`.
6. Uncomment the "TestFlight build" section at the bottom of
   `.github/workflows/build-ipa.yml` — it archives, signs, and uploads
   to App Store Connect (build number auto-increments on each signed run).
7. Install from **TestFlight** on your iPhone.

## Install — if you ever get a Mac

1. Open `TeslaDash.xcodeproj` in **Xcode 26+**.
2. Select the TeslaDash target → Signing & Capabilities → pick your
   **Team** (free Apple ID works for running on your own phone; the
   signature lasts 7 days, same as AltStore).
3. Connect your iPhone, pick it as the run destination, press Run.
4. On the iPhone, trust the developer certificate under
   Settings → General → VPN & Device Management.

## Pairing (first run, one time)

1. Stand next to the car with your phone and a Tesla **key card**.
2. Open TeslaDash → **Pair your Tesla** → enter the **17-character VIN**
   (driver's door jamb, windshield plate, or Tesla app → Controls →
   Software).
3. The app creates your phone key and sends the pairing request.
4. **Tap the key card on the center console** (just below the screen) and
   confirm on the touchscreen.
5. The app reconnects and verifies the key. Done — the phone is now a key
   for the car. It connects automatically whenever you're in the car.

To unpair: Settings → Unpair this Tesla. This deletes the phone key from
the Keychain; the car's key list keeps the entry until you remove it in
the car (Controls → Locks → Keys).

## Demo mode

Settings → Mode → **Demo (simulated)**. The app simulates a full drive
cycle — parked, driving around Los Angeles, charging — with moving speed,
battery drain, odometer, GPS, and tire pressures. Use it in the iOS
simulator (CoreBluetooth doesn't work in the simulator) or to show the app
to someone without the car nearby. Nothing in demo mode touches Bluetooth.

## Project layout

```
TeslaDash.xcodeproj/            Xcode project (iOS 17, Swift 6)
TeslaDash/
  TeslaDashApp.swift            @main entry point
  Info.plist                    Bluetooth + location usage strings,
                                bluetooth-central background mode
  Assets.xcassets/              App icon + accent color
  Models/
    VehicleState.swift          Provider-agnostic snapshot the UI reads
    Trip.swift                  Trip model + local JSON store
    PanelKind.swift             Swappable dashboard panels
  Services/
    VehicleDataProvider.swift   Provider protocol + AppCommand
    TeslaBLEProvider.swift      Real car over BLE (swift-tesla-ble)
    DemoDataProvider.swift      Simulated driving
    PairingService.swift        First-time key pairing flow
    LocationProvider.swift      Phone GPS for the live map
    TripLogger.swift            Records trips from live drive state
  ViewModels/
    DashboardViewModel.swift    Single source of truth for all views
  Views/
    ContentView.swift           Root: pairing gate + tab bar
    PairingView.swift           VIN entry + key-card tap flow
    DashboardView.swift         Portrait dashboard + swappable panels
    ClusterView.swift           Landscape instrument cluster
    MapPanelView.swift          MapKit map + routing + ETA
    TirePressureView.swift      Per-wheel pressures
    MediaPanelView.swift        Now playing + transport controls
    TripHistoryView.swift       Locally logged trips
    SettingsView.swift          Mode, units, panels, pairing, about
.github/workflows/build-ipa.yml GitHub Actions: unsigned .ipa for AltStore (+ commented-out TestFlight upgrade)
.github/icon-1024.b64           App icon as base64 text — the CI build
                                decodes it and generates all 9 icon sizes
                                (the icon PNGs themselves are not committed)
```

## Honest limits

- **Bluetooth range is ~10 m.** The phone must be in or near the car.
  There is **no remote access** — lock/unlock from another city needs the
  Fleet API, which this app deliberately does not use.
- **Foreground dashboard.** The app works while open in the car.
  Background BLE is declared (`bluetooth-central`), but iOS may suspend
  the app; background trip logging is best-effort.
- **Car must be awake for infotainment data** (drive, charge, climate,
  media). The app wakes the car automatically; while driving this is a
  non-issue.
- **Map uses the phone's GPS**, not the car's. The BLE library's snapshot
  type doesn't expose the car's `LocationState`, and the phone is in the
  car anyway, so the position is the same.
- **ETA and battery-on-arrival are estimates** computed on-device from
  the MapKit route (~0.33% of pack per mile). They are not car signals.
- **Tire pressure is read over BLE** (`TirePressureState` in the
  protocol), but richer signals some apps advertise (tire temperature,
  blind-spot, brake temp, G-force) are **not** in this protocol — verify
  against your car before trusting any of them.
- **Firmware drift.** Tesla changes protobuf fields and behaviors over
  time (e.g. encrypted responses only on 2024.38+). If a Tesla update
  breaks a field, the fix is in the `swift-tesla-ble` library, not this
  app — update the package and rebuild.
- **Key loss = pairing loss.** The phone key is device-only in the
  Keychain. A new phone means re-pairing (tap the key card again).

## Things I could not verify without a Mac / real car

- **The app has never been compiled.** It was written on a Linux VM with
  no Xcode. The Swift code was written against the real
  `swift-tesla-ble` API (read from the repo, not guessed), but the first
  build on a Mac (or in CI) is where real compile errors would surface.
- **BLE against the real car is untested.** The library is
  fixture-tested against Tesla's Go reference, but only a parked 2024
  Model 3 Highland proves end-to-end pairing and polling.
- **Whether `swift-tesla-ble`'s `BLETransport` supports CoreBluetooth
  state preservation/restoration** (surviving app termination in the
  background) — the library source was not checked for a restore
  identifier. Treat background relaunch as unverified.
- **Whether the car reports tire pressure on a 2024 Highland** over this
  path — the field exists in the protocol, but only the real car answers
  it.
- **TestFlight upload path is unverified.** The commented-out TestFlight
  section uploads during export (`destination: upload` in
  `ExportOptions.plist`, Xcode 16+) instead of the deprecated `xcrun
  altool`. Verify on the first signed run.
- **Dependency pin.** `swift-tesla-ble` is pinned in the project to
  commit `e179465a191bd6e5c8114ee3dfe08dca6a3ec363` — the exact commit
  the API was verified against. No `Package.resolved` is committed yet;
  Xcode generates one on first resolve — commit it once you have it so
  CI reproduces the exact dependency graph.
- **iOS 17 minimum, not 16.** The `swift-tesla-ble` package declares
  iOS 17+ (`Package.swift` platforms), so the app targets iOS 17.0.
  iPhone 14 Plus runs iOS 17+ fine.
- **Export compliance.** `ITSAppUsesNonExemptEncryption` is set to
  `false` in Info.plist on the basis that the app only uses Apple's
  CryptoKit primitives; confirm this is right for your App Store
  submission.

## License

App code here is yours to use. `swift-tesla-ble` is MIT-licensed. This
project is not affiliated with or endorsed by Tesla, Inc.
