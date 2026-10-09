#import <Foundation/Foundation.h>
#include <stdint.h>
#include <signal.h>
#include <stdatomic.h>

// Internal interface. Read-only contract check; never changes service or radio.
NSDictionary *NWBTSkywalkCompatibility(void);
// Also checks the actual HCI nexus descriptor, without opening any channel.
NSDictionary *NWBTNativeAvailability(void);
NSDictionary *NWBTDiagnosticContract(void);
// Legacy ACT and ACL call paths retain the exact inspected-device restriction.
NSDictionary *NWBTLegacyGuard(void);
NSDictionary *NWBTLegacyCompatibility(void);
NSDictionary *NWBTNativeGuard(void);
void *NWBTOpenNativeChannel(NSString *protocol, uint64_t *capacity, NSDictionary **error);
// Called only after guarded service retirement, before consuming/sending frames.
// Waits for asynchronous driver ownership release; never retries HCI commands.
void *NWBTOpenExclusiveNativeChannel(NSString *protocol, uint64_t *capacity, NSDictionary **error);
void NWBTCloseNativeChannel(void *channel);
// Shared by the radio loop, the private control thread and signal handlers.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Cancellation must remain signal-safe");
FOUNDATION_EXPORT atomic_int NWBTCancelled;
