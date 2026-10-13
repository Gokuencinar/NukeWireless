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
