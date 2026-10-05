#ifndef NWBT_LAB_H
#define NWBT_LAB_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define NWBT_LAB_HANDLE 0xee
#define NWBT_LAB_ROTATION_COUNT 10
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
static inline size_t NWBTLabManufacturerData(uint8_t p[35]) {
    // Keep flags and our 128-bit service. Replace the name with a test-only
    // manufacturer field so the legacy advertisement remains within 31 bytes.
    NWBTLabData(p);
    const uint8_t manufacturer[] = {9, 0xff, 0xff, 0xff, 'N','W','L','a','b', 1};
    memcpy(p + 25, manufacturer, sizeof manufacturer);
    p[3] = 31;
    return 35;
}
static inline size_t NWBTLabRotatingData(uint8_t p[35], unsigned sequence) {
    if (sequence >= NWBT_LAB_ROTATION_COUNT) return 0;
    NWBTLabManufacturerData(p);
    p[9] = 0x22; // Separate lab service: 7AD172A1-6D8C-4D0A-9BEA-8D8F3B5C9C22.
    const uint8_t marker[] = {'N', 'W', 'R', 'o', 1, (uint8_t)sequence};
    memcpy(p + 29, marker, sizeof marker);
    return 35;
}
static inline void NWBTLabSwiftPairParameters(uint8_t p[25]) {
    NWBTLabParameters(p);
    // Microsoft's normal Swift Pair cadence: 244 * 0.625 ms = 152.5 ms.
    p[3] = p[6] = 0xf4; p[4] = p[7] = 0; p[5] = p[8] = 0;
}
static inline size_t NWBTLabSwiftPairData(uint8_t p[35]) {
    // Microsoft Swift Pair's LE-only vendor section, with a lab display name.
    // This finite discovery test does not implement a pairable GATT accessory.
    const uint8_t advertisement[] = {
        2, 1, 6,
        11, 0xff, 0x06, 0x00, 0x03, 0x00, 0x80, 'N','W','L','a','b'
    };
    memset(p, 0, 35);
    p[0] = NWBT_LAB_HANDLE; p[1] = 3; p[2] = 1; p[3] = sizeof advertisement;
    memcpy(p + 4, advertisement, sizeof advertisement);
    return sizeof advertisement + 4;
}
static inline size_t NWBTLabApplePairingData(uint8_t p[35]) {
    // Fixed AirPods Pro proximity-pairing research fixture (company 0x004C,
    // subtype 0x07). One identity, ordinary cadence, finite controller duration.
    const uint8_t advertisement[31] = {
        0x1e, 0xff, 0x4c, 0x00, 0x07, 0x19, 0x07, 0x0e, 0x20,
        0x75, 0xaa, 0x30, 0x01, 0x00, 0x00, 0x45, 0x12, 0x12, 0x12,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    p[0] = NWBT_LAB_HANDLE; p[1] = 3; p[2] = 1; p[3] = sizeof advertisement;
    memcpy(p + 4, advertisement, sizeof advertisement);
    return 35;
}
static inline void NWBTLabFastPairParameters(uint8_t p[25]) {
    NWBTLabParameters(p);
    // Google discoverable-provider cadence: 160 * 0.625 ms = 100 ms.
    p[3] = p[6] = 0xa0; p[4] = p[7] = p[5] = p[8] = 0;
}
static inline size_t NWBTLabFastPairData(uint8_t p[35]) {
    // Fixed Pixel Buds model fixture from Modern; discovery only, no GATT pairing.
    const uint8_t advertisement[] = {
        2, 1, 6, 3, 3, 0x2c, 0xfe, 6, 0x16, 0x2c, 0xfe, 0xcd, 0x82, 0x56
    };
    memset(p, 0, 35);
    p[0] = NWBT_LAB_HANDLE; p[1] = 3; p[2] = 1; p[3] = sizeof advertisement;
    memcpy(p + 4, advertisement, sizeof advertisement);
    return sizeof advertisement + 4;
}
static inline void NWBTLabEnable(uint8_t p[6], int enable) {
    memset(p, 0, 6); p[0] = enable ? 1 : 0; p[1] = 1; p[2] = NWBT_LAB_HANDLE;
    if (enable) { p[3] = 0xe8; p[4] = 3; } // Controller stops after 10 seconds.
}
#endif
