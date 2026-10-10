#include "../src/NWRouteNeighbors.h"
#include <assert.h>
#include <stdio.h>

static size_t route(uint8_t *b, unsigned index, const uint8_t ip[4], const uint8_t mac[6]) {
    /* The 18-byte sockaddr_dl rounds to 20, not 24. Include a third address to
     * catch an incorrect pointer-size alignment, as well as the 96-byte header.
     */
    const uint16_t length = 96 + 16 + 20 + 4, iface = (uint16_t)index;
    const uint32_t addrs = 7;
    memset(b, 0, length); memcpy(b, &length, 2); b[2] = 5;
    memcpy(b + 4, &iface, 2); memcpy(b + 12, &addrs, 4);
    b[96] = 16; b[97] = 2; memcpy(b + 100, ip, 4);
    b[112] = 18; b[113] = 18; b[117] = 4; b[118] = 6;
    memcpy(b + 120, "en0x", 4); memcpy(b + 124, mac, 6);
    b[132] = 4; b[133] = 2;
    return length;
}
int main(void) {
    uint8_t table[512], result[6] = {0};
    const uint8_t ip[4] = {192, 0, 2, 1}, other[4] = {192, 0, 2, 2};
    const uint8_t mac[6] = {0x48, 0x96, 0xd9, 0xf6, 0xa8, 0x65};
    size_t length = route(table, 7, ip, mac);
    assert(NWRouteFindIPv4MAC(table, length, ip, 7, result));
    assert(!memcmp(result, mac, 6));
    assert(!NWRouteFindIPv4MAC(table, length, other, 7, result));
    assert(!NWRouteFindIPv4MAC(table, length, ip, 8, result));
    assert(!NWRouteFindIPv4MAC(table, length, ip, 0, result));
    for (size_t i = 0; i < length; ++i)
        assert(!NWRouteFindIPv4MAC(table, i, ip, 7, result));
    uint8_t saved = table[118]; table[118] = 0;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[118] = saved;
    table[117] = 12;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[117] = 4;
    table[132] = 40;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[132] = 4;
    size_t second = route(table + length, 7, ip, mac);
    assert(NWRouteFindIPv4MAC(table, length + second, ip, 7, result));
    table[length + 129] ^= 1;
    assert(!NWRouteFindIPv4MAC(table, length + second, ip, 7, result));
    table[length + 129] ^= 1;
    table[124] = 0xff;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result));
    puts("Routing neighbour parser passed"); return 0;
}
