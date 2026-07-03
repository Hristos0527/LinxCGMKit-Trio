# Changelog

All notable changes to LinxCGMKit-Trio. Fork development **Jun 2026 – Jul 2026**.

Author: **Hristos** ([@Hristos0527](https://github.com/Hristos0527))

---

## [1.0.0] - 2026-07-03 — Public release

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
- LinxReader NS upload should remain **OFF** when using Trio (avoids duplicate SGV curves)

---

## Development history (pre-release)

Reconstructed from Trio working-tree builds and backup snapshots. Not every Trio build touched LinxCGMKit — entries below are Linx/CGM-specific only.

### 2026-06-22 — Kit scaffold (Build #1)

- `LinxCGMKit/` directory created (no plugin wiring yet)

### 2026-06-23 — Initial integration (Build #3)

- `LinxCGMKit/` copied from LoopBuild fork
- Xcode workspace, `project.pbxproj`, `PluginManager.swift` wiring
- Simulator + `Debug-iphoneos` **BUILD SUCCEEDED**

### 2026-06-24 — 3-minute loop cycle attempt (Builds #6–14)

- Trio `loopCycleInterval` set to **3 × 60 s**
- `GlucoseStorage.filterTime` set to **2.5 × 60 s** (do not filter samples within 3 min window)
- Part of intensive overnight device testing cycle

### 2026-06-25 – 2026-06-26 — Loop gate refinement (Builds #21–25)

- `Config.loopInterval` toggled between 3 and 5 minutes during experiments
- Settled on **5 min loop + 4.5 min gate** (`loopGateMinimumInterval = 270 s`)
- LinxCGMKit `loopCycleInterval` aligned with Trio loop config during this period

### 2026-06-27 — Glucose / Nightscout deduplication (Build #27)

- Duplicate SGV curve fix — glucose/NS deduplication
- LinxReader NS upload **OFF** recommended to avoid double uploads

### 2026-06-30 — Plugin active, loop gate & dedup (Build #32)

- LinxCGMKit plugin fully active in Trio
- Loop **5 min** + **4.5 min gate** (`Config.loopGateMinimumInterval`)
- Glucose/NS deduplication further improved

### 2026-06-30 — 3-minute loop restored (Build #51)

- **3-minute loop** restored: `Config.loopInterval` = 180 s, `loopGateMinimumInterval` = 150 s (2.5 min)
- `LinxCGMManager.loopCycleInterval` = **180 s** — BLE heartbeat (`providesBLEHeartbeat`) delivers fresh sample ~every 3 min → `FetchGlucoseManager` → `deviceDataManager.heartbeat()` → loop cycle
- `GlucoseStorage.filterTime` = 2.5 min (do not filter samples under 3 min)
- Reconstructed from Build #26 Equil restore baseline; Garmin/hypo timer reverted (Linx unchanged by hypo work)

### 2026-07-03 — Background BLE scan fix (Build #52)

- **Background `AllowDuplicatesKey: true`** — every advertisement callback processed in background (3 min gate still filters Loop output)
- **Scan restart watchdog** — if `lastSampleSentAt` or last advertisement > 4 min in background: `stopScan` → `startScan`
- **Heartbeat scan kick** — `fetchNewDataIfNeeded` / `resumeScanning` starts fresh scan cycle in background
- **Diagnostic logging** — `lastAdvertisementAt`, scan state, fg/bg (`os_log` + DeviceLog)
- Fixes overnight CGM gap (00:26–01:20) caused by iOS background BLE throttling

### Builds with no Linx changes

Builds **#1** (partial Equil only), **#6–14** Equil-heavy builds, **#28**, **#53**, **#54**, **#55** did not modify LinxCGMKit (verified by diff or changelog attribution).
