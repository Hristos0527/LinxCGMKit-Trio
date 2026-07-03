# Integrating LinxCGMKit into Nightscout Trio

Minimal Trio-side changes to register and run LinxCGMKit. The CGM logic lives in this repo.

## 1. Add as git submodule

```bash
git submodule add https://github.com/Hristos0527/LinxCGMKit-Trio.git LinxCGMKit
git submodule update --init --recursive
```

Place at `LinxCGMKit/` in the Trio workspace root (alongside other CGM kits).

## 2. Xcode workspace

Add to `Trio.xcworkspace/contents.xcworkspacedata`:

```xml
<FileRef
   location = "group:LinxCGMKit/LinxCGMKit.xcodeproj">
</FileRef>
```

In the **Trio** app target:

1. Link `LinxCGMKit.framework` and `LinxCGMKitUI.framework`
2. **Embed & Sign** both frameworks

## 3. Register the CGM plugin

**File:** `Trio/Sources/APS/PluginManager.swift`

```swift
import LinxCGMKit
import LinxCGMKitUI
```

Add to `BasePluginManager.cgms`:

```swift
CgmPluginDescription(
    pluginIdentifier: LinxCGMManager.pluginIdentifier,
    localizedTitle: String(localized: "LINX CGM"),
    manager: LinxCGMManager.self
),
```

## 4. CGM picker option

**File:** `Trio/Sources/Helpers/CGMOptions.swift`

```swift
import LinxCGMKit

CGMOption(
    name: "LINX CGM",
    predicate: { $0.type == .plugin && $0.id == LinxCGMManager.pluginIdentifier }
),
```

## 5. Skip double calibration for Nightscout upload

LinxCGMKit applies its own two-point calibration in `LinxDecoder`. Trio must **not** run `CalibrationService` again on Linx readings (avoids offset duplicate on Nightscout).

**File:** `Trio/Sources/APS/FetchGlucoseManager.swift`

In `overcalibrate(entries:)`:

```swift
// LinxCGMKit applies its own two-point calibration in LinxDecoder; skip Trio
// CalibrationService so we don't create a second, offset glucose stream on NS.
if cgmManager?.pluginIdentifier == "LinxCGMManager" {
    return entries
}
```

## 6. Plugin bundle (optional)

`LinxCGMPlugin` implements `CGMManagerUIPlugin`. If your Trio build uses static registration (step 3), linking the frameworks is sufficient. For Loop-style dynamic plugin loading, build and embed `LinxCGMPlugin.loopplugin`.

## 7. User setup flow

1. Trio → CGM source → select **LINX CGM**
2. Enter sensor serial number (or pick from nearby scan list)
3. Set two-point calibration in the plugin settings UI
4. Confirm glucose appears in Trio and Nightscout (if enabled)

## 8. Build and test checklist

- [ ] Clean build Trio + LinxCGMKit
- [ ] CGM list shows “LINX CGM”
- [ ] Sensor serial filter matches your Linx device
- [ ] Glucose updates at ~3 min intervals in foreground
- [ ] Background test: lock phone 10+ min — readings should resume (watchdog + heartbeat kick)
- [ ] Nightscout values match plugin calibration (no double offset)

## Reference

- This repo: Build **#55** state (includes background scan watchdog #52)
- Trio fork glue: `PluginManager.swift`, `CGMOptions.swift`, `FetchGlucoseManager.swift`
- Linx BLE: service UUID `181F`, manufacturer little-endian `0x0059`
