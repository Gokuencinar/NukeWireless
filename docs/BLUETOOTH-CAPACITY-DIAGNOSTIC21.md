# Diagnostic21: optional advertising capacity query

App `2.0.0~diagnostic21` / 20021; Bluetooth `2.0.0~diagnostic8`.
Based on diagnostic20, retaining its Wi-Fi name resolution, diagnostic16 unblock
fix and diagnostic19 iPad presentation handling.

## Evidence

The tester's diagnostic18 report on iPhone10,2 / 20H240 successfully completed
five local queries over UART: 131 received bytes, five successful responses,
configuration restored and Bluetooth service preserved. This resolves the earlier
read-only UART timeout in that observation. It does not prove advertising.

Its 64-byte Supported Commands bitmap is the fixture in
`tests/test_bt_advertising.m`. Octet 36 is `0x7f`: extended advertising setters,
enable and per-set address are advertised, but bit 7 (Read Number of Supported
Advertising Sets, opcode `0x203b`) is absent. Removal is advertised in octet 37.
Bluetooth diagnostic7 required all these bits, so the exact tester bitmap fails
its advertising preflight. Simply deleting bit 295 from the guard is insufficient:
the previous catalog route subsequently submitted `0x203b` unconditionally.

Command mapping is from Bluetooth Core, Vol 4, Part E,
[Supported Commands and LE Read Number of Supported Advertising Sets](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-60/out/en/host-controller-interface/host-controller-interface-functional-specification.html).
The report contains only `le_capabilities`, not an advertising attempt, so this
is a reproducible preflight blocker, not a claim that every reported failure had
the same cause. Firmware acceptance of setters remains to be tested physically.

## Change

The mandatory guard retains every setter, address, enable and removal command
used by these tests. It treats the capacity query separately. A single model
never queries capacity. For multiple models, the query is sent only when the
controller advertises it. An advertised query which fails is still an error;
malformed replies, missing setters or zero available sets are not bypassed.

If capacity cannot be queried, or the reported count is smaller than the
selection, the worker uses one handle and schedules models in turn. It does not
invent a supported-set count. Each model receives its existing profile and stable
address, with ACKs required for parameters, address, data and enable. The set is
disabled with an ACK before reconfiguration. The operation shares a ten-second
overall advertising deadline; each enable also has a finite controller duration.
No firmware resets, extra permissions, payload changes or increased rate/power
are introduced. Controllers with sufficient verified capacity retain simultaneous
advertising. Stop, exclusive ownership and independent recovery remain intact.

The existing finally block disables and removes the owned handle even after
cancellation, a lost enable completion or failure during reconfiguration. If
cleanup cannot be acknowledged, UART service preservation remains prohibited.
Diagnostics retain schedule, capacity-query support and enabled-model count even
when an oversized event is summarized. An ACK never proves external reception.

## Validation

Host C tests cover mandatory versus optional bitmap bits. The Foundation test
exercises the actual worker advertising/session code with a deterministic HCI
peer: exact tester bitmap; single, sequential and simultaneous selections;
insufficient and zero capacity; total and per-enable duration; stable identity;
Stop; rejected data; lost enable ACK; cleanup failure; missing setter; fixed
single-profile route and repetition. It does not emulate physical Bluetooth.

Compilation, package verification and physical tester acceptance are pending.
