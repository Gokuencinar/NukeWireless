#import <Foundation/Foundation.h>

// Capability inspection only. This version does not send Bluetooth packets.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTInspectTransport(void);
// Read-only snapshot of the loaded Apple transport's code for ABI analysis.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *NWBTCopyTransportCode(void);
