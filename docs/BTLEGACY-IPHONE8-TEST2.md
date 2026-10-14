# Bluetooth legacy iPhone 8 Plus diagnostic 2 — ACK-confirmed stop

## Physical evidence from tester (14 October 2026)

Exact admitted device: iPhone10,2, iOS 16.7.4 (20H240), Dopamine rootless.
The tester installed commit `b086623` and the diagnostic JSON confirms worker
`2.0.0~diagnostic9`, despite the original app logging `2.0.0~diagnostic21`.
For one AirPods 2 model the BLE legacy commands received these HCI completions:

| Command | HCI status |
| --- | --- |
| 0x1001, 0x1002, 0x2003 capability reads | 0 (success) |
| 0x2005 random address | 0 (success) |
| 0x2006 advertising parameters | 0 (success) |
| 0x2008 advertising data | 0 (success) |
| 0x200A enable | 0 (success) |
| 0x200A disable between models | 0 (success) |
| 0x200A final redundant disable | 12 (Command Disallowed) |

The test lasted around ten seconds. `controller_advertising_acknowledged=true`,
`advertising_stopped_acknowledged=false` (because the old logic overwrote the
first successful stop with the redundant failed one), `service_restored=true`,
`transmission_verified=false`. A second scanner has not confirmed receiving RF.
The older extended path had rejected 0x2036 with status 1. Do not rerun it.

## Candidate change

- Branch `btlegacy-iphone8-diagnostic2`, isolated from stable and from the
  previous tested `btlegacy-iphone8-diagnostic1` branch.
- App version `2.0.0~btlegacy2`, worker `2.0.0~diagnostic10`, unified package
  version `2.0.0~btlegacy2+bundle1`.
- Track successful 0x200A disable ACKs. An ACK-confirmed stop is final; do not
  submit the same command again. If stop lacks an ACK, retry in cleanup and
  engage independent recovery if unsuccessful. Mock test explicitly rejects
  duplicate disables with status 0x0c and requires exactly two HCI 0x200A
  submissions (enable + disable) per model.
- Send a distinct guardian completion only when the report confirms 0x200A
  stop ACK and UART closure/configuration restoration. The guardian still
  retires/restarts bluetoothd, but skips a redundant emergency 0x200A. If
  the worker dies or the stop ACK is missing, it attempts emergency stop.
- Guard against falsely reporting bluetoothd recovery when bootout fails or
  the daemon PID did not change. Ensure lock/pipe FDs have close-on-exec before
  spawning launchctl. These are fail-closed safety fixes, not evidence of RF.

## Retest instructions

Keep the previous working package and a backup of the app data. Reboot the
iPhone, turn Bluetooth off in Settings, install ONLY the `iphoneos-arm64`
Dopamine/rootless unified DEB, and use Bluetooth > Random devices > AirPods 2
for one ten-second run. Do not tap Advertise all yet. Export latest.json
immediately without clearing the journal and, if possible, use an external
BLE scanner to check reception. Confirm that Bluetooth is functional afterward.
If it stops working or hangs, stop testing and restore the previous package.
An HCI enable ACK is not proof of receiving RF signals; a bluetoothd PID
change is not proof that radio advertising stopped if firmware misbehaves.

The earlier btlegacy1 DEB and its SHA-256 must remain available for rollback.
