#ifndef NWBT_LAB_H
#define NWBT_LAB_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define NWBT_LAB_HANDLE 0xee
static inline size_t NWBTLabReplySize(uint16_t opcode) {
    switch (opcode) {
        case 0x2036: case 0x203b: return 2;
        case 0x2035: case 0x2037: case 0x2039: case 0x203c: return 1;
        default: return 0;
    }
}
static inline void NWBTLabParameters(uint8_t p[25]) {
    memset(p, 0, 25); p[0] = NWBT_LAB_HANDLE;
    p[1] = 0x10; // Legacy ADV_NONCONN_IND through the extended command family.
    p[3] = p[6] = 0x40; p[4] = p[7] = 0x06; // 1000 ms; no address rotation.
    p[9] = 7; p[20] = p[22] = 1; // All advertising channels; LE 1M.
    p[19] = 20; // Maximum standard HCI requested power; controller selects actual supported power.
    // Public address, no peer, connections or scan response.
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
static inline size_t NWBTLabFastPairPower(uint8_t p[35], int power) {
    // AD Tx Power Level uses signed dBm. Use the controller's selected power,
    // never the requested maximum; this is not a GFPS distance calibration.
    if (power < -127 || power > 20 || p[3] != 14) return 0;
    p[18] = 2; p[19] = 0x0a; p[20] = (uint8_t)(int8_t)power; p[3] = 17;
    return 21;
}
#define NWBT_LAB_PLATFORM_COUNT 3
#define NWBT_LAB_MULTI_HANDLE 0xe0
static inline size_t NWBTLabMultiDeviceData(uint8_t p[35], unsigned platform, unsigned model) {
    if (platform<1 || platform>3 || model>=3) return 0;
    if (platform==1) {
        const char *names[]={"NWLab Keyboard","NWLab Mouse","NWLab Audio"};
        size_t length=strlen(names[model]); memset(p,0,35);
        const uint8_t head[]={2,1,6,0,0xff,6,0,3,0,0x80};
        p[0]=NWBT_LAB_MULTI_HANDLE+model;p[1]=3;p[2]=1;p[3]=10+length;
        memcpy(p+4,head,sizeof head);p[7]=6+length;memcpy(p+14,names[model],length);
        return 14+length;
    }
    size_t length;
    if (platform==2) {
        const uint16_t products[]={0x200e,0x2014,0x200a};
        length=NWBTLabApplePairingData(p);p[11]=products[model]&0xff;p[12]=products[model]>>8;
    } else {
        const uint8_t models[3][3]={{0xcd,0x82,0x56},{0,0,0x47},{0x14,0,0x45}};
        length=NWBTLabFastPairData(p);memcpy(p+15,models[model],3);
    }
    p[0]=NWBT_LAB_MULTI_HANDLE+model;return length;
}
static inline size_t NWBTLabDeviceAddress(uint8_t p[7], unsigned platform, unsigned model) {
    if(platform<1 || platform>3 || model>=3) return 0;
    // Separate lab static-random identities, unchanged for the whole emission.
    const uint8_t address[]={NWBT_LAB_MULTI_HANDLE+model,model+1,0,platform,0x57,0x4e,0xc2};
    memcpy(p,address,sizeof address);return sizeof address;
}
static inline size_t NWBTLabDeviceEnable(uint8_t p[6], int enabled, unsigned model) {
    if(model>=NWBT_LAB_PLATFORM_COUNT) return 0;
    memset(p,0,6);p[0]=enabled ? 1 : 0;p[1]=1;p[2]=NWBT_LAB_MULTI_HANDLE+model;
    if(enabled) { p[3]=0xe8;p[4]=3; }
    return 6;
}
static inline void NWBTLabEnable(uint8_t p[6], int enable) {
    memset(p, 0, 6); p[0] = enable ? 1 : 0; p[1] = 1; p[2] = NWBT_LAB_HANDLE;
    if (enable) { p[3] = 0xe8; p[4] = 3; } // Controller stops after 10 seconds.
}
#endif
