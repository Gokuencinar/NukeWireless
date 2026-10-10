#include "../src/NWRouteNeighbors.h"
#include <assert.h>
#include <stdio.h>

static size_t route(uint8_t *b, unsigned index, const uint8_t ip[4], const uint8_t mac[6]) {
    /* The 18-byte sockaddr_dl rounds to 20, not 24. Include a third address to
     * catch an incorrect pointer-size alignment, as well as the 92-byte header.
     */
    const uint16_t length = 92 + 16 + 20 + 4, iface = (uint16_t)index;
    const uint32_t addrs = 7;
    memset(b, 0, length); memcpy(b, &length, 2); b[2] = 5;
    memcpy(b + 4, &iface, 2); memcpy(b + 12, &addrs, 4);
    b[92] = 16; b[93] = 2; memcpy(b + 96, ip, 4);
    b[108] = 18; b[109] = 18; b[113] = 4; b[114] = 6;
    memcpy(b + 116, "en0x", 4); memcpy(b + 120, mac, 6);
    b[128] = 4; b[129] = 2;
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
    uint8_t saved = table[114]; table[114] = 0;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[114] = saved;
    table[113] = 12;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[113] = 4;
    table[128] = 40;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result)); table[128] = 4;
    size_t second = route(table + length, 7, ip, mac);
    assert(NWRouteFindIPv4MAC(table, length + second, ip, 7, result));
    table[length + 125] ^= 1;
    assert(!NWRouteFindIPv4MAC(table, length + second, ip, 7, result));
    table[length + 125] ^= 1;
    table[120] = 0xff;
    assert(!NWRouteFindIPv4MAC(table, length, ip, 7, result));
    puts("Routing neighbour parser passed"); return 0;
}
