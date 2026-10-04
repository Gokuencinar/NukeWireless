# Bluetooth Modern → NukeWireless dev27

Source examined: pepeangell5/ESP32-TOOLS-MODERN, commit dc59cd372530d17633efd20b8a2421c3e60cfdfe (MIT, José Ángel Chávez Félix / PepeAngell). This is a new Objective-C implementation of the scanner behavior, rather than an Arduino binary conversion.

## Implemented

Info > Bluetooth > BLE Scanner: explicit permission request on scan, 15-second foreground scans, up to 30 devices sorted by RSSI, names, advertised manufacturer company ID and bytes, service UUIDs, connectable flag and last-seen age. Data is held in memory and scanning stops when leaving the screen, entering the background, losing radio availability, or tapping Stop. No peripheral connection, pairing, driver takeover or Bluetooth daemon restart is involved.

CoreBluetooth reports a local device UUID, not an on-air Bluetooth address. UUIDs cannot be used as addresses for the existing Classic L2CAP ping. BLE-only advertisements do not discover every Classic headset, particularly when it is already connected and not advertising BLE. Manufacturer/company labels are unauthenticated advertisement data. RSSI does not establish physical distance.

## Not ported

Modern has three Bluetooth menu entries: BLE Scanner, BLE Spam and BT Disruptor. Radio Jammer is a separate RF tool requiring nRF24 hardware.

BLE Spam creates raw advertisements for Apple, Samsung, Microsoft and Google profiles and changes the ESP32 random address. Public CBPeripheralManager.startAdvertising supports local name and service UUIDs only, so these raw manufacturer profiles cannot be reproduced using that API.

BT Disruptor's Connect Flood, L2CAP Ping Storm, Spoof Identity and Chaos all update BLE advertisements. updateL2CAPStormData writes manufacturer bytes to setAdvertisementData: it does not issue L2CAP echo requests. updateSpoofIdentityData sets an ESP32 random address; it does not prove a cloned identity or a successful disconnection. NukeWireless does not expose these labels as functioning iOS attacks.

A future native transmission implementation requires evidence from the actual iPhone XS / iOS 16.3.1 driver ABI, LE controller capabilities, advertising transport and independent restoration path. The existing Classic ping transport does not by itself establish LE advertising support. No unverified private selectors, guessed driver calls or packet flood were added.

## Validation

Build uses CoreBluetooth in device, compatibility and simulator targets. The development package includes NSBluetoothAlwaysUsageDescription. English and Spanish strings are UTF-8. Unit fixtures cover fragmented/absent manufacturer data, invalid RSSI (127), record merging and immutable snapshots. Simulator fixtures cover BLE list rendering and stopping on background/navigation without requesting hardware access. Radio discovery still requires an on-device acceptance test with Bluetooth enabled and the permission granted.

Apple documentation: https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:)
Original source: https://github.com/pepeangell5/ESP32-TOOLS-MODERN/tree/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src
