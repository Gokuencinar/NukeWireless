#import <Foundation/Foundation.h>
#define NWBT_VERSION @"0.0.3~app8"

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
// Experimental, bounded five-echo diagnostic on the exact inspected device.
// Requires exclusive HCI/ACL ownership; never stops system services itself.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTL2Ping(NSString *destination);
