#import <Foundation/Foundation.h>
#include <stdint.h>
#include <signal.h>

// Internal interface. Only the ABI-guarded inspector calls this transport.
NSDictionary *NWBTNativeGuard(void);
void *NWBTOpenNativeChannel(NSString *protocol, uint64_t *capacity, NSDictionary **error);
void NWBTCloseNativeChannel(void *channel);
FOUNDATION_EXPORT volatile sig_atomic_t NWBTCancelled;
