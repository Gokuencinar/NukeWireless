#ifndef NWBT_LAB_H
#define NWBT_LAB_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define NWBT_LAB_HANDLE 0xee
static inline size_t NWBTLabReplySize(uint16_t opcode) {
    switch (opcode) {
        case 0x2036: return 2;
        case 0x2037: case 0x2039: case 0x203c: return 1;
        default: return 0;
    }
}
static inline void NWBTLabParameters(uint8_t p[25]) {
    memset(p, 0, 25); p[0] = NWBT_LAB_HANDLE;
    p[1] = 0x10; // Legacy ADV_NONCONN_IND through the extended command family.
    p[3] = p[6] = 0x40; p[4] = p[7] = 0x06; // 1000 ms; no address rotation.
    p[9] = 7; p[20] = p[22] = 1; // All advertising channels; LE 1M.
    // Public address, 0 dBm, no peer, connections or scan response.
}
static inline size_t NWBTLabData(uint8_t p[35]) {
    const uint8_t advertisement[] = {
        2, 1, 6,
        17, 7, 0x21,0x9c,0x5c,0x3b,0x8f,0x8d,0xea,0x9b,0x0a,0x4d,0x8c,0x6d,0xa1,0x72,0xd1,0x7a,
        6, 9, 'N','W','L','a','b'
    };
    p[0] = NWBT_LAB_HANDLE; p[1] = 3; p[2] = 1; p[3] = sizeof advertisement;
    memcpy(p + 4, advertisement, sizeof advertisement);
    return sizeof advertisement + 4;
}
static inline void NWBTLabEnable(uint8_t p[6], int enable) {
    memset(p, 0, 6); p[0] = enable ? 1 : 0; p[1] = 1; p[2] = NWBT_LAB_HANDLE;
    if (enable) { p[3] = 0xe8; p[4] = 3; } // Controller stops after 10 seconds.
}
#endif
