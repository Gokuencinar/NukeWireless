#import <Foundation/Foundation.h>
#include <stdint.h>
#include <signal.h>
#include <stdatomic.h>

// Internal interface. Only the ABI-guarded inspector calls this transport.
NSDictionary *NWBTNativeGuard(void);
void *NWBTOpenNativeChannel(NSString *protocol, uint64_t *capacity, NSDictionary **error);
void NWBTCloseNativeChannel(void *channel);
// Shared by the radio loop, the private control thread and signal handlers.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Cancellation must remain signal-safe");
FOUNDATION_EXPORT atomic_int NWBTCancelled;
