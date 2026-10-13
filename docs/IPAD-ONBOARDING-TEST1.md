# iPad onboarding preliminary candidate: `2.0.0~ipadtest1`

## Scope and rationale

Isolated branch `ipad-onboarding-diagnostic1` from `968751b` (`diagnostic21`). The iPad Pro on iPadOS 16.0 (Dopamine) shows the welcome view, and after tapping **Continue** the display turns black instead of opening the application menu. This is a candidate workaround and diagnostic build, **not a proven fix** or a public/stable release. The full original SwiftUI `SplashView`/onboarding implementation is compiled and its source is unavailable.

## Changes

- `src/NukeWirelessInfo.m`: on iPad only, the existing two-second UI timer also checks the current foreground key window for the original three-host tab controller. When it is present and attached after an onboarding/body transition, the existing idempotent UI installer is retried. It never substitutes the root controller or overwrites onboarding preferences. The same check can detect late transitions after the old 12-second diagnostic window. It leaves iPhone behavior unchanged.
- `src/NWPresentationDiagnostics.*`: limited `ui_onboarding` observations at about 16, 60, 120 and 240 seconds while tabs are absent, plus a pre/post-reconciliation snapshot on the first attached tab or if the custom tab bar has been detached. The `awaiting-main-tabs` phase is **not an error** if the user is still reading the welcome screen.
- `tests/UIRegression.swift` and `scripts/test_ui_simulator.sh`: separate opt-in tests for immediate (2 s) and late (16 s) Continue, in both languages, checking three original hosts, four displayed choices, attached content, window geometry and compact traits on iPad. Existing tests remain the default.
- Package version is distinct from `2.0.0~diagnostic21`. It intentionally retains the diagnostic8 Bluetooth worker and unrelated network features.

## Test procedure on the physical iPad

1. Install the **Dopamine/rootless** candidate matching `iphoneos-arm64`, not the RootHide (`iphoneos-arm64e`) or rootful (`iphoneos-arm`) package. This candidate has the **same Debian package ID** as the installed app and will **replace** its version, not run alongside it. Preserve a known-good `.deb` and app data before replacing; no automatic changes are made to a tester's device by building this branch.
2. Open NukeWireless and show the welcome screen. Record Continue → menu/black-screen behavior with the time since opening, the iPad model, iPadOS and exact package version. Try one immediate Continue and, on a fresh launch/onboarding only when naturally available, one delayed Continue (>15s). Do not erase preferences solely to repeat onboarding.
3. If the interface turns black, keep the app in the foreground long enough for one or two two-second reconciliation passes. Without clearing the journal, collect `Files → On My iPad → NukeWireless → NukeWireless-Diagnostics → latest.json` and the screen video, if the app's Documents are visible. The event `ui_onboarding: tabs-after-welcome` means the tab controller was found and UI installation was attempted; it **does not prove that the pixels were visible or tappable**. `awaiting-main-tabs` with no later tabs supports a remaining welcome/transition failure but does not prove which Swift callback failed.
4. Check foreground return, portrait/landscape and native tab interactions. Keep original and candidate logs distinct.

## Verification boundary

Windows supports Python/package/static tests and Bash syntax checks. The actual Objective-C/Swift UIKit build, simulator runtime and `.deb` assembly require macOS CI-generated Mach-O binaries and the pinned original application package. A simulated SwiftUI Welcome fixture does not execute the proprietary/pinned Swift callback. **Do not label this as physically validated on iPadOS 16.0 until the tester confirms it.**

## Candidate delivery and verification (2026-10-13)

- Source: `ipad-onboarding-diagnostic1` initial implementation commit `e518cd8e1f7628894071d9ca5c5b15522a292d9a`, independent of `audit-rh25.5` / stable. Mac GitHub Actions run [38424215117](https://github.com/Gokuencinar/NukeWireless/actions/runs/38424215117) compiled the iOS 15 app/adapter and Bluetooth worker and passed its navigation/foreground regression; generated `nuke-wireless-compatibility` artifact. Verified downloaded `build-manifest.json` `version=2.0.0~ipadtest1`, target `arm64-ios15.0`, matching source commit.
- iPad simulator [run 38424215254](https://github.com/Gokuencinar/NukeWireless/actions/runs/38424215254): six orientation/onboarding jobs (`off`, `immediate`, `late` × portrait/landscape) returned **success** on the latest attempt. The first portrait/off attempt failed one diagnostic modal presentation check (`NWDiagnosticsUIRegressionPresent`, result index 31=1), although four background/foreground cycles passed; rerunning failed jobs resulted in success for all six jobs. Treat this as potentially timing-sensitive rather than dismissing the first failure. iPadOS 16 *physical* remains untested.
- Reassembled from original pinned base SHA-256 `83b8f4364194ecabda0e516659568e7e92af656c0cfa82222ccb596239bfc128`; Mac artifact extracted into `build/`. App DEBs generated for all three bootstraps, Bluetooth worker unchanged, unified package tested for all three.
- Physical tester target: `dist/ipadtest1-unified/com.gokuencinar.nukewireless_2.0.0~ipadtest1+bundle1_iphoneos-arm64.deb` (**Dopamine/rootless**), SHA-256 **`6c463d33687c4186498d41f5ad394064250b89fa9376e6fcdbd002a909a5562f`**. Convenient local copy `E:\Descargas CoS\NukeWireless\NukeWireless-iPadTest1-Dopamine-iOS15plus.deb`, byte-identical.
- `tests/test_package.py`: 7 PASS; `tests/test_compat_package.py --artifact build`: 8 PASS; `tests/test_unified_package.py --inputs dist/ipadtest1-inputs --output dist/ipadtest1-unified`: 6 PASS/3 SKIP (Linux root dpkg only); `tests/test_embedded_ui.py`: 2 PASS/1 SKIP (no optional standalone base input); `tests/test_native_abi.py`: PASS. Checked `git diff --check`. No installation performed on the tester device.

This diagnostic **will overwrite the currently installed NukeWireless package**, since its dpkg identifier is unchanged. Keep the previous working DEB available to restore, and back up app data before installation. Do not publish it as an official version or claim the iPad black screen fixed based on simulated tests alone.
