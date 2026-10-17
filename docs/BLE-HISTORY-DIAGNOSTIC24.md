# BLE filters, history and signal detail — diagnostic24

Continues diagnostic23, including router-independent Wi-Fi names and the accepted iPhone10,2/20H240 UART cleanup fix. Bluetooth privileged worker version/sources remain diagnostic11.

Bluetooth → BLE Scanner has search (name, company, CoreBluetooth UUID, service) and All / Named / Connectable filters. These affect display, not the radio scan. Scanning remains explicitly started, 15 seconds, up to 30 devices, stopped on background or leaving the scanner area. Opening signal detail preserves the current scan and offers Stop; returning to the list keeps its deadline. No connections, location access, maps or background scanning are introduced.

Each callback updates an immutable record with valid RSSI (-127…20; 127 is unavailable), advertisement count and at most 60 samples at half-second resolution. Detail shows a signal-versus-time graph with VoiceOver summary, min/max/average, recent signal, detection times/count, company, UUID, services, connectable flag and the existing bounded manufacturer-data preview. RSSI is not converted to distance or direction and company data is not authenticated identity.

History is local in Documents/NukeWireless-BLE/history.json, separate from redacted diagnostics. Up to 200 UUID entries, 60 samples each; oldest entries evicted. First/last wall-clock times and counts survive sessions. UUID changes may create separate records. Raw manufacturer/service payloads and locations are not stored. Reads/writes/export are bounded and performed on a serial background queue, with atomic writes, local file permissions and iOS data protection. Load merges new arrivals; clearing invalidates pending loaded records. Invalid stored data is reported and retained until explicit clear. Snapshot writes occur at most once every three seconds during observation and when stopping.

History supports the same filters, detail, confirmed deletion and deliberate JSON export via the share sheet (anchored for iPad). Export includes names, UUIDs, services, times and signal samples; the UI explains this. Technical diagnostics only record counts and storage error codes.

Validation covers merging/samples/filters, unavailable RSSI, bounds, persisted roundtrip, load/clear races, export, malformed-file preservation, scanner/detail Stop, existing Wi-Fi coexistence and bilingual UI screenshots. iOS native compilation and simulator checks require macOS CI. Physical feature acceptance on the reference phone remains pending until manually exercised.
