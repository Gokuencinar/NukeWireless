#import <Foundation/Foundation.h>
#define NWBT_VERSION @"0.0.3~app20"
#import "../NWBluetoothLimits.h"

// Passive capability inspection; this entry point sends no Bluetooth packets.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTInspectTransport(void);
// Read-only snapshot of the loaded Apple transport's code for ABI analysis.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTCopyTransportCode(void);
// Explicit exclusive controller diagnostic; requires Bluetooth off in Settings.
// Sends only Read Local Version Information to the local controller, no echo.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTReadControllerInfo(void);
// Opens and closes only the actual HCI Skywalk nexus. No slot is consumed or written.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTOpenSkywalk(void);
// Submits one standard local version query through the inspected HCI Skywalk ring.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTReadSkywalkController(void);
// Five allowlisted local HCI reads, bounded to twelve seconds. Requires the
// runner's exclusive ownership and recovery; does not enable radio operations.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTReadLECapabilities(void);
// Fixed nonconnectable NWLab announcement, 1 second interval, 10 second
// controller duration. Runner owns exclusive transport and service recovery.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTAdvertiseLab(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTAdvertiseManufacturerLab(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTAdvertiseRotatingLab(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTAdvertiseSwiftPairLab(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTAdvertiseApplePairingLab(void);
// Before retiring bluetoothd, verify its state is readable and Bluetooth off.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTVerifyBluetoothOff(void);
// Experimental, bounded echo diagnostic on the exact inspected device.
// Requires exclusive HCI/ACL ownership; never stops system services itself.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTL2Ping(NSString *destination);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTL2PingWithOptions(NSString *destination, NSUInteger count, NSUInteger intervalSeconds);
// Millisecond spacing; legacy exports above retain their seconds-based ABI.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTL2PingWithMilliseconds(NSString *destination, NSUInteger count, NSUInteger intervalMS);
