# Dopamine compatibility test candidate — 14 October 2026

App: `2.0.0~diagnostic22+compat1`, build marker `NWBuild-compatdiag1`, CFBundleVersion `20025`.
Bluetooth component: `2.0.0~diagnostic11`. Unified package: app version plus `+bundle1`.
Branch: `dopamine-compat-audit1`, based on BTLegacy2 `70ee2e6`.
This candidate preserves the diagnostic16 Wi-Fi unblock path and the subsequent
tablet, names, embedded UI and legacy Bluetooth fixes. It does not replace the
stable branch or claim physical acceptance on new hardware.

## Changes

- Explicit candidate admission for iOS 26 / Darwin 25, instead of applying the
  old `iOS + 6` rule to the renamed OS. iOS 15–18 pairs remain admitted; mismatched
  pairs and later kernels are refused. UART still has its exact iPhone10,2 /
  16.7.4 / 20H240 guard; this change does not open UART on uninspected devices.
- Bluetooth still checks manager signatures, all channel exports, valid registry
  identifiers, bounded channel properties and HCI replies before advertising.
  Advertising family selection now requires both LE features and the supported
  command bitmap on every transport, before the first setter. A rejected extended
  command never triggers a legacy fallback.
- PF admits Darwin 25 using the existing struct contract, then validates read-only
  status/rule copyouts before any mutation. Rules remain limited to the identified
  hotspot client and NukeWireless ownership. Policy rejection has errno 0 rather
  than a stale unrelated errno. Helper reports include the failing stage, kernel
  major, contract readback, compiled struct sizes and owned-rule packet counters.
- Both directions in native Wi-Fi device menus use the checked bridge. Individual
  blocking excludes the gateway, local device, subnet/broadcast and shared link
  identities. The launch adapter verifies one current en0 peer against the ARP
  table and current gateway, replaces stale native destination arguments, and
  refuses to spawn a rejected task. PID/state getters for that task report 0/off.
- Packet/restoration bindings belong to each task, replacing the shared pending
  binding. New blocks require the current scan/network epoch. Leaving the app
  invalidates admission; releasing an owned block remains possible with its
  matching device identity. An epoch is not an observation of a BSSID change.
- Correct recovered scan status ABI: signed 32-bit `int`, checked before hooking.
- Legacy selection commands share the operation deadline. A partial selection
  remains an error and is visible; successful completion and a clean explicit
  Stop remain quiet. The independent guardian and verified restoration survive.
- Fixed Fast Pair diagnostic model ID is derived from the transmitted fixture.

## Diagnostics

Every export includes hardware model, iOS numeric version/build, kernel release,
package scheme/source and expected worker, without requiring an environment test.
Environment check now also probes the hotspot helper read-only and records
Bluetooth manager method encodings and channel symbol presence. Wi-Fi records
operation/peer tags, current packet-role validation and process evidence. It never
labels a local process or an HCI acknowledgement as confirmed loss of Internet or
external radio reception. Private traces are bounded and contain labels only.

## Contract sources

The slot and seven PF struct declarations were compared against Apple's XNU
8020.101.4, 8792.61.2, 10002.1.13, 11215.1.10 and exact commit
[`f6217f891ac0bb64f3d375211650a4c1ff8ca1ea`](https://github.com/apple-oss-distributions/xnu/tree/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea).
The normalized declarations match. This is source evidence, not a capture of the
tester's exact iOS 26.0.1 kernel or private Bluetooth framework. Runtime rejection
remains possible and must be read from the new report. The
[Dopamine 3.0.11 release](https://github.com/opa334/Dopamine/releases/tag/3.0.11)
documents an iOS 26 beta regression fix; it does not validate NukeWireless.

## Tester acceptance still needed

Install the Dopamine/rootless unified DEB and allow Sileo to resolve the external
dependencies (`arpoison`, `network-cmds`, `ldid` and the bootstrap injection API).
The Bluetooth component is inside this DEB. Check the exact app version above,
then run Info → Diagnostics → Check environment and installation.

On the iOS 26 tester, check single-device block/unblock while observing both the
selected device and the previously affected TV; check hotspot block/unblock with
mobile data disabled on the client; check advertising with sender Bluetooth off
in Settings. Export JSON immediately after each failure. iOS 26 PF writes, HCI
radio operation and real per-peer isolation remain unverified until those tests.

Tests cover the actual task veto/interleaved binding code, identity policy,
version pairs, real advertising-session feature and slow-reply faults, existing
restoration tests and simulator navigation. CI and package evidence are recorded
in the delivery manifest, separately from physical acceptance.
