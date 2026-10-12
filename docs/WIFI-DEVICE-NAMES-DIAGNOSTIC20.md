# Wi-Fi device names — diagnostic20

Based on diagnostic19; retains the diagnostic16 Wi-Fi unblock fix, the iPad
presentation review and Bluetooth diagnostic7 without changes to radio code.

## Cause and implementation

The compatibility adapter previously queued serial `getnameinfo` calls, saved
successful replies in preferences and only applied them on a later discovery.
It attempted each MAC once during the process lifetime. It did not browse Bonjour.

The extension now uses public Foundation Bonjour browsing and DNS-SD PTR queries.
Names update the actual native device model and the searchable presentation snapshot
as evidence arrives, including evidence received before the native device callback.
Names published by services such as AirPlay, Cast, SMB and printers can supplement
reverse DNS. Pairing IDs and UUID-only service names are not displayed as friendly
names; RAOP's hardware prefix is removed. `.local` and the terminal DNS dot are
trimmed, with length and control-character validation.

Custom nicknames and saved aliases take precedence. Useful existing native names
are preserved. For unresolved native names, friendly Bonjour service names take
precedence over Bonjour hostnames, then reverse DNS. Ties are deterministic.
Fallback labels retain the IP suffix. No vendor or exact device model is invented
from a private MAC address.

Discovery is read-only and bounded: 15 declared service types, at most 128 unique
services and peers, eight simultaneous service resolutions and eight PTR lookups,
three seconds per lookup, 12 seconds of Bonjour browsing and a 30-second session.
All DNS-SD scheduling/deallocation and model changes belong to main; DNS work is
asynchronous. Refresh, backgrounding and a replaced session cancel outstanding
work. Updates recheck scan generation, interface tuple and the current IP/MAC.
An old PTR reply cannot rename a different MAC at the same IP. Evidence is session
memory, not a new persistent history. Old saved names and user aliases are retained.

The obsolete adapter lookup queue is removed; its block/unblock implementation is
unchanged. All installers declare `NSBonjourServices` and a Local Network usage
description. DNS-SD uses the system library already linked by the Apple toolchain; no
additional APT dependency is added.
If prompted, local network access must be allowed. Routers and devices that do not
publish names, or isolate clients, can still yield fallback labels.

Diagnostics include aggregate `name_resolution` counters and a `wifi_names` event;
these contain no hostnames, MACs or IPs. Counts are observations, not identity proof.

## References and provenance

LocalFence was inspected at commit `d7356ad840b83efb28313e71353e23295e7be23b`:
[Bonjour discovery](https://github.com/emp0ry/LocalFence/blob/d7356ad840b83efb28313e71353e23295e7be23b/app/Sources/LFBonjourDiscovery.m)
and its identity resolver demonstrate the benefit of local service evidence.
LocalFence is GPL-3.0-or-later. This change implements public protocol/API behavior
independently; it does not vendor LocalFence source or platform-classification rules.

API references: [Apple Bonjour](https://developer.apple.com/documentation/foundation/bonjour),
[Local Network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[Apple DNS-SD header](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/dns_sd.h).

## Validation

`tests/test_device_names.m` checks normalization, malformed PTR records, evidence
priority, early discovery, address reuse and cancelled callbacks without networking.
The existing device-actions simulator regression additionally checks native/custom
name priority, stale generations, changed IP/MAC/network context, and live snapshot
updates. Package tests check Bonjour declarations for each scheme.

Build, package and UI results are recorded separately from physical name discovery.
No additional names on the user's Wi-Fi are confirmed until the new build is tested
there. Physical iPadOS 16 presentation acceptance remains pending as in diagnostic19.
