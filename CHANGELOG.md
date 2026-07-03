# Changelog

All notable changes to LinxCGMKit-Trio are documented here.

## [1.0.0] - 2026-07-04

Initial public community release (Trio Build #55 state).

### Added

- `LinxCGMManager` plugin for Trio (`CGMManager` + SwiftUI settings)
- Passive BLE scan (`LinxScanner`) for Linx service `181F` / manufacturer `0x0059`
- Two-point calibration (`LinxDecoder`) with in-plugin calibration UI
- Serial-number filter and nearby sensor discovery list
- **3-minute loop cycle gate** (`loopCycleInterval = 3 * 60`)

### Fixed / improved

- **Background scan watchdog** (Build #52): `backgroundScanStaleInterval = 4 * 60` — stop/start scan when no fresh advertisements in background
- Heartbeat-driven scan kick when app is backgrounded (`restartScan` on Loop heartbeat)
- Single shared `CBCentralManager` without State Restoration ID (fixes CGM delete/re-add BLE conflicts)
- `AllowDuplicates` enabled for continuous advertisement reception

### Notes

- Original CGM plugin — **not** from AndroidAPS
- Author: Hristos (@Hristos0527)
