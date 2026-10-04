#import <Foundation/Foundation.h>
#define NWBT_VERSION @"0.0.2~probe4"

// Capability inspection only. This version does not send Bluetooth packets.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTInspectTransport(void);
// Read-only snapshot of the loaded Apple transport's code for ABI analysis.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTCopyTransportCode(void);
// Explicit exclusive controller diagnostic; requires Bluetooth off in Settings.
// Sends only Read Local Version Information to the local controller, no echo.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTReadControllerInfo(void);
