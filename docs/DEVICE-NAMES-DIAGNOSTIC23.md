# Device names without router access — diagnostic23

Built on diagnostic22+compat1; Bluetooth worker sources/version unchanged (diagnostic11).

Wi-Fi name discovery keeps the native scanner and user aliases. It adds RFC 1002 wildcard NBSTAT queries (UDP 137) and unicast UPnP root-device discovery (UDP 1900), followed by a local HTTP GET of the advertised device description. Google Cast Bonjour TXT `fn` is used as a friendly name; `md` and `id` never become names or manufacturer claims.

No router login, DHCP lease scraping, registration, authentication, subscriptions, or device-control commands. No new binaries/dependencies/entitlements. The app's existing Local Network permission applies. UPnP local HTTP uses NSAllowsLocalNetworking; redirects, credentials and proxies are disabled for these requests.

Only discovered IPv4 peers on en0 are queried. Maximum 128 peers / 256 UDP queries, eight active sockets, two seconds per query, 32 documents, four concurrent fetches, four seconds per document, 64 KiB document limit. The existing 30-second naming session owns cancellation. Interface IPv4/netmask/index and per-session peer MAC are checked before accepting callbacks; the scan bridge also checks generation/network epoch and preserves custom names. HTTP LOCATION must contain the exact peer's literal IPv4. UDP responses must originate from that peer (NBSTAT additionally checks port and transaction). Name evidence is descriptive, not authenticated identity or authority for blocking. A device that does not respond keeps its existing fallback.

Priority: custom/existing native names preserved by the scan bridge; otherwise DNS PTR 20, NBSTAT 30, Bonjour host 40, UPnP friendlyName 50, Bonjour instance 60, Google Cast fn 70. Models are not substituted for names. No inference of Apple from a private MAC.

Diagnostics contain only query/result/error counts, no names, IPs, MACs or URLs. Tests cover malformed/truncated NetBIOS, compression, groups, suffixes, transaction mismatches, random inputs, URL peer restrictions, malformed/oversized XML, entity declarations, nested/duplicate friendlyName, TXT priorities and session cancellation. Native/Objective-C tests require the macOS CI; Windows verifies the pure C parser.

Protocol sources:
- https://www.rfc-editor.org/rfc/rfc1002 (sections 4.2.17–18)
- https://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf (unicast M-SEARCH, LOCATION, device friendlyName)
- https://raw.githubusercontent.com/chromium/chromium/main/chrome/browser/media/router/discovery/mdns/media_sink_util.cc (fn vs md)
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking

Acceptance: refresh Wi-Fi on different routers with Windows/NAS/TV devices that advertise names, preserve an alias, leave/re-enter the app, repeat refresh. Build/simulator tests do not prove names will be published by every device; physical acceptance remains pending until observed.
