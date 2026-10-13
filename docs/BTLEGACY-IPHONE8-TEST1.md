# Experimental Bluetooth legacy path — iPhone 8 Plus

Candidate `2.0.0~btlegacy1` with worker `2.0.0~diagnostic9` based on the isolated `ipad-onboarding-diagnostic1` branch. This is a **test**, not a confirmed hardware fix.

## Physical evidence

The Dopamine/rootless iPhone10,2 on iOS 16.7.4 (20H240) reports LE feature bitmap `ff03000000000000` (extended advertising bit 12 absent) and successfully reads local HCI commands. The first actual extended advertising command `0x2036` returned HCI status `0x01` (Unknown HCI Command); the extended cleanup command `0x203c` also returned `0x01`. No advertising was enabled. The old preflight checked the supported-command bitmap alone and incorrectly inferred that extended advertising was usable.

## Candidate behavior

- The narrow, existing UART admission still requires exactly iPhone10,2 / 20H240 / iOS16.7.4. Other iOS versions and devices retain the extended advertising path unchanged.
- Before sending any advertising command, a read-only `0x2003` query checks feature bit 12. When absent, requires supported legacy command bits before choosing `0x2005` static random address, `0x2006` parameters, `0x2008` data, and `0x200a` enable. Legacy advertisements are nonconnectable and do not enable pairing or a scan response. Never interleave extended and legacy commands on the same HCI session.
- All selected models are sent **sequentially**, never concurrently. The maximum total advertised duration requested by the host is ten seconds. Each model requires a successful HCI completion before moving forward. Cleanup always requests `0x200a` disable and requires an ACK. The legacy random address is a test-specific static random identity, not the phone's public address.
- Legacy commands have **no controller-enforced duration**. A separately spawned recovery process is armed before the worker opens UART. It has a 22-second independent hard deadline, kills a stalled worker, attempts a second explicit `0x200a` disable after the UART port closes, and retires/restarts bluetoothd regardless of whether that second disable succeeded. **This reduces risk but cannot mathematically guarantee radio deactivation if iOS or the controller itself stops responding.** Successful tests always retire/restart bluetoothd after legacy commands to restore its global random-address state.
- Controller acceptance is *not* proof that nearby devices received an advertisement. No permanent changes or root access beyond the existing signed installed worker package are introduced.

## Test procedure

1. On the exact iPhone 8 Plus, keep a copy of the previously installed `diagnostic21` package and back up app data. This test uses the same Debian package identifier, so it replaces the installed app, rather than installing side by side. It is not meant for the iPad Pro.
2. **Restart the iPhone first**, to clear any controller mode left by previous extended advertising attempts. Disable Bluetooth from **Settings**, not just Control Center, as required by this guarded experiment.
3. Launch the app; enter Bluetooth → Random devices; select **one** model and run the normal ten-second diagnostic. Do not test Advertise All until a single model completes and the controller is verified to have stopped. Wait for the Bluetooth service to recover.
4. Export `NukeWireless-Diagnostics/latest.json` immediately, without clearing the journal or running another read-only capabilities test. Report `advertising_mode`, command opcodes/ACKs, `advertising_stopped_acknowledged`, `service_restored`, `controller_interface_ready`, and whether a separate BLE scanner actually observed the signal.
5. If Bluetooth fails to recover or the app hangs, stop testing and revert to the previously known-good DEB. A successful local HCI ACK is not equivalent to proof of safe RF operation.

## Verification status

Run native HCI/advertising mock tests, macOS cross-compile and package verification before deploying. These do not replace a real test on iPhone10,2. The previous iPad onboarding tests are preserved, but the package is intended to diagnose the Bluetooth issue.
