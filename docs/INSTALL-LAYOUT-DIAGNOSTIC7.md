# Diagnostic7: installed product names

The previous packages retained two visible filesystem names from the original
app. Diagnostic7 changes the installed layout in all three bootstrap variants:

| Component | Installed path (relative to the jailbreak root) |
| --- | --- |
| App | `Applications/NukeWireless.app` |
| Executable | `Applications/NukeWireless.app/NukeWireless` |
| Network helpers | `usr/libexec/nukewireless` |

Dopamine/rootless adds `/var/jb/`; RootHide continues to relocate the bootstrap.
The RootHide sidecars follow the renamed executables. No legacy compatibility
symlink is installed. The existing package ID is preserved so dpkg removes the
previous owned files during upgrade. User preferences and documents are not
deleted. The installer keeps the canonical archive paths from bundle3 and does
not reintroduce firmware installation bounds.

## Runtime integration

`NWInstallLayout.h` supplies the installed names to native callers and the
Python packagers. The adapter translates paths still constructed by the pinned
Swift binary before adding the bootstrap prefix. Wi-Fi and hotspot image lookup,
the Bluetooth app-root lookup, and the privileged helpers' exact parent-path
checks all use the new executable name. Bluetooth's changed runner is versioned
as `2.0.0~diagnostic2`.

The SHA-pinned Aegis patch changes its two suffix literals and five length
instructions while preserving ADR targets, its ABI and its same-root parent
validation. `tests/test_install_layout.py --baseline <pinned-baseline.deb>`
executes the actual ARM64 validation code with Unicorn 2.1.4. It accepts the new
paths under the same root and rejects old names, other roots and extra suffixes.
This tests the authorization code, not packet transmission on an iPhone.

The stable signing/bundle identifier `me.midnightchips.harpy-reloaded`, Swift
runtime class names and preference keys remain internal compatibility values.
Changing them without rebuilding the unavailable original Swift sources could
break permissions, runtime lookup or access to existing user data. Historical
source snapshots, notices, package replacement metadata and input-baseline paths
also retain their original names. These do not create legacy installed paths.
`build_nuke_info_deb.py` produces a staging core in the pinned input layout;
deliver the output of `build_compat_debs.py` / `build_unified_deb.py` only.

## Validation status

- Local layout and ARM64 parent-validation tests: passed.
- Fresh compilation: passed for source commit
  `3378895f46b60b6e5bde34f41bc09472c426211e`.
- Simulator regression: 46 checks and four background/foreground cycles per
  language (English and Spanish), passed.
- Final DEB inspection: eight compatibility tests, six locally runnable unified
  tests and three layout/ARM64 whitelist tests, passed. The three Linux-only
  tests skipped on Windows ran successfully in Linux CI.
- Isolated Linux dpkg tests cover fresh install, upgrade from old split/unified
  layouts, ownership and removal for RootHide/rootless/rootful: passed in CI.
- Physical upgrade, opening, scanning, block/unblock and Bluetooth repetition:
  pending; previous-version acceptance is not evidence for this renamed build.

CI on 10 October 2026:

- [Compatibility compile and UI](https://github.com/Gokuencinar/NukeWireless/actions/runs/38064128551)
- [Development compile and UI](https://github.com/Gokuencinar/NukeWireless/actions/runs/38064128546)
- [Isolated dpkg migration](https://github.com/Gokuencinar/NukeWireless/actions/runs/38064128561)

Unified `2.0.0~diagnostic7+bundle1` delivery SHA-256:

| Bootstrap | SHA-256 |
| --- | --- |
| RootHide (`iphoneos-arm64e`) | `4104c319f83e37722bba1df720727aa459c623474de55f71cd5df8bdf4bb6c96` |
| Dopamine/rootless (`iphoneos-arm64`) | `55bc50d415bacef8078dcc02d1d9bca454b9b9040ebc8ec0a76c4570ca4af40b` |
| Rootful (`iphoneos-arm`) | `fbe6e474f00d0eb0c240e679efe4ec10b426a9c5e0ac60b1db2ebe7f0694a296` |
