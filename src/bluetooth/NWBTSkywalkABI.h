#ifndef NWBT_SKYWALK_ABI_H
#define NWBT_SKYWALK_ABI_H
#include <stdint.h>
#include <stddef.h>
#include "../NWCompatibility.h"

// Same contract in Apple's XNU 8020.101.4, 8792.61.2, 10002.1.13 and
// 11215.1.10 os_channel.h. See docs/BLUETOOTH-SKYWALK-PORT.md for evidence.
typedef struct {
    uint16_t flags, length;
    uint32_t index;
    uint64_t externalPointer, bufferPointer, metadataPointer;
    uint32_t reserved[8];
} NWBTSkywalkSlotProperties;
_Static_assert(sizeof(NWBTSkywalkSlotProperties) == 64, "Skywalk slot size");
_Static_assert(offsetof(NWBTSkywalkSlotProperties, bufferPointer) == 16, "Skywalk buffer offset");
enum {
    NWBTSkywalkFirstTX = 0,
    NWBTSkywalkFirstRX = 2,
    NWBTSkywalkSyncTX = 0,
    NWBTSkywalkSyncRX = 1,
    NWBTSkywalkBufferSize = 4
};
static inline int NWBTSkywalkOSAllowed(unsigned ios, unsigned darwin) {
    return NWTransportOSContract(ios, darwin);
}
// Extended advertising setters, per-set address and removal. Capacity querying
// is optional: the tester's 20H240 controller advertises these setters but not
// Read Number of Supported Advertising Sets (octet 36, bit 7).
// Bluetooth Core's Local Supported Commands bitmap, also observed on 20D67.
static inline int NWBTExtendedAdvertisingCommands(const uint8_t *commands, size_t length) {
    if (!commands || length != 64) return 0;
    const unsigned bits[] = {289, 290, 291, 293, 296};
    for (size_t i = 0; i < sizeof(bits) / sizeof(bits[0]); ++i)
        if (!(commands[bits[i] / 8] & (1u << (bits[i] % 8)))) return 0;
    return 1;
}
static inline int NWBTAdvertisingCapacityQuery(const uint8_t *commands, size_t length) {
    return commands && length == 64 && (commands[36] & 0x80) != 0;
}
#endif
