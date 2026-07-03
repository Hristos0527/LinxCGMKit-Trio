# LinxCGMKit for Trio

## Author

**Hristos** ([@Hristos0527](https://github.com/Hristos0527)) — developer and maintainer of this community plugin.

- Self-tested on personal daily use (~2 weeks) before release
- LinxCGMKit: original CGM plugin

A **LoopKit `CGMManager` plugin** that reads the **Linx BLE glucose sensor** via passive advertisement scanning and feeds glucose to [Nightscout Trio](https://github.com/nightscout/Trio).

> **Original CGM plugin** — not ported from AndroidAPS.

## Features

- Passive BLE scan of Linx sensor advertisements (service `181F`, manufacturer ID `0x0059`)
- Serial-number filtering and nearby-device picker
- Two-point calibration UI (built into the plugin)
- **3-minute loop gate** — one `NewGlucoseSample` per cycle to drive Trio heartbeat
- **Background scan watchdog** (Build #52): restarts scan after ~4 min of stale data when the app is backgrounded
- Continuous scanner with `AllowDuplicates` for reliable background reception
- State restoration ID intentionally omitted to avoid CGM delete/re-add BLE conflicts

## Hardware

- **Linx CGM sensor** broadcasting BLE advertisements
- iPhone with Bluetooth LE (iOS 17+)

## Real-world use

I have been **using this integration on myself daily for ~2 weeks** (Linx CGM with Trio on iOS) before publishing.

Personal testing (~2 weeks, n=1) does **not** replace clinical validation or your own safety testing.

## Modules

| Module | Role |
|--------|------|
| `LinxCGMKit` | `LinxScanner`, `LinxDecoder`, `LinxCGMManager` |
| `LinxCGMKitUI` | SwiftUI settings, calibration, sensor picker |
| `LinxCGMPlugin` | `CGMManagerUIPlugin` entry point |

## Build requirements

- macOS with **Xcode 15+**
- **iOS 17+**
- **LoopKit** and **LoopKitUI** from your Trio workspace
- Optional: regenerate `.xcodeproj` with [XcodeGen](https://github.com/yonatasnark/XcodeGen): `xcodegen generate` (see `project.yml`)

Add `LinxCGMKit/LinxCGMKit.xcodeproj` to your Trio `.xcworkspace` and link `LinxCGMKit.framework` + `LinxCGMKitUI.framework` into the Trio app target.

## Trio integration

See **[INTEGRATION.md](INTEGRATION.md)**.

## Changelog

See **[CHANGELOG.md](CHANGELOG.md)**.

## License

[AGPL-3.0](LICENSE)

## Disclaimer

This software is provided **as-is** for **experienced developers** who build and install Trio themselves.

- **Not a medical device.** Not reviewed or approved by any regulatory authority.
- **Use at your own risk.** You are solely responsible for building, installing, configuring, and operating this software with your CGM sensor.
- **No warranty.** The authors assume **no liability** for hypo/hyperglycemia, incorrect readings, sensor failure, or any harm arising from use or misuse.
- **Not official support** from Linx, Nightscout, or Trio maintainers unless explicitly stated.
- **Test thoroughly** — cross-check against an approved CGM; consider open loop / pump-off-body testing first.

By building or using this code, you accept full responsibility for your diabetes management decisions.
