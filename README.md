# SunTimes

Watch-only watchOS app whose complication shows the next sun event: blue hour, golden hour, sunrise or sunset. Intended as a replacement for the built-in Sunrise/Sunset complication.

## Definitions (standard photographic)

| Phase       | Sun elevation      |
|-------------|--------------------|
| Blue hour   | -6° to -4°         |
| Golden hour | -4° to +6°         |
| Sunrise/set | centre at -0.833°  |

Times come from the NOAA solar equations (`Shared/SolarCalculator.swift`), generalised to arbitrary elevation angles. Accuracy is within ~1 minute of published tables.

## Complication families

- **Corner** – event icon, with "Golden 18:42" curved along the edge
- **Circular** – gauge of progress toward the next event, icon + time inside
- **Inline** – "Sunset 19:12 · Blue 19:40"
- **Rectangular** – current phase + the next three events

The widget timeline has one entry per event boundary, so the face flips to the next event exactly on time with no polling.

## Build

1. Install Xcode (App Store) and point the CLI at it:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   ```
2. Install XcodeGen and generate the project:
   ```sh
   brew install xcodegen
   cd SunTimes
   xcodegen generate
   open SunTimes.xcodeproj
   ```
3. In Xcode, select your Team under *Signing & Capabilities* for **both** targets (or set `DEVELOPMENT_TEAM` in `project.yml`). The App Group `group.com.marcowarm.SunTimes` must be enabled on both targets; XcodeGen already adds it to the entitlements. If the bundle IDs clash with something in your account, change `com.marcowarm` in `project.yml`.
4. Run the `SunTimesWatch` scheme on a simulator or your watch.
5. Open the app once and grant location access, then add the **Sun Times** complication to a watch face.

### Location

- The app requests *When In Use* location and caches the last fix in the shared App Group.
- The widget extension has `NSWidgetWantsLocation` so it can refresh location itself; if that fails or times out (4 s) it falls back to the cached fix. Sun times change negligibly over tens of kilometres, so a stale fix is fine.
- In the simulator, set a location via *Features > Location* on the paired iPhone simulator or the watch simulator.

## Verifying the maths without Xcode

```sh
./Scripts/verify.sh
```

Compiles the shared solar code with the macOS toolchain and prints events for London, Berlin, Sydney, New York and Tromsø (polar day) next to reference sunrise/sunset times.

## Keeping a free-account build alive

Apps signed with a free (personal team) Apple ID expire after 7 days. `Scripts/resign-to-watch.sh` rebuilds, re-signs and re-installs the app on your watch; `Scripts/install-launch-agent.sh` runs it automatically.

1. Create your local config from the template (`.env` is git-ignored):
   ```sh
   cp .env.example .env
   ```
   Find your watch's identifier (UDID or CoreDevice identifier) with `xcrun devicectl list devices` (pick the row whose *Reality* is `physical`, not a simulator) and set it in `.env`:
   ```sh
   SUNTIMES_WATCH_ID=<your-watch-id>
   ```
   The team ID is taken from the *Apple Development* certificate in your keychain. If you have several, also set `SUNTIMES_TEAM_ID`. See `.env.example` for all options. To keep the file elsewhere, point `SUNTIMES_ENV_FILE` at it.
2. Try it once: `./Scripts/resign-to-watch.sh --force`
3. Install the launch agent: `./Scripts/install-launch-agent.sh` (remove with `--uninstall`).

The agent checks every 3 hours and re-installs once 20 hours have passed since the last success, so a day when the watch is unreachable is retried automatically. It builds from a private copy of the working tree in `~/Library/Caches/SunTimes`, so the project you open in Xcode is not touched. Logs go to `~/Library/Logs/SunTimes/auto-resign.log`; if installs keep failing for 5 days, you get a macOS notification.

Two macOS privacy rules shape this setup:

- Background jobs cannot read `~/Documents`, `~/Desktop` or `~/Downloads`, so keep the repository somewhere else (e.g. `~/Developer`). After moving it, run `install-launch-agent.sh` again.
- Background processes that aren't apps cannot reach devices on the local network, so the agent runs the script through a small helper app (`~/Library/Application Support/SunTimes/SunTimes Auto-Resign.app`) that the installer generates. If macOS asks whether it may find devices on your local network, allow it.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

See the [NOTICE](NOTICE) file for attribution and contributor details:
> "This app includes watchOS complication code developed by Marco Warm."
