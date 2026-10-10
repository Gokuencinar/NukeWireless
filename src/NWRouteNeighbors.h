#ifndef NW_ROUTE_NEIGHBORS_H
#define NW_ROUTE_NEIGHBORS_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* Darwin routing socket wire layout, from hotspot/vendor/net/route.h (Apple
 * XNU): rt_msghdr is 92 bytes on arm64; sockaddr records use 4-byte rounding.
 * Neither size follows sizeof(long). No socket operations or packet emission.
 */
#define NW_ROUTE_HEADER_SIZE 92u
static inline int NWRouteFindIPv4MAC(const void *buffer, size_t size,
                                     const uint8_t ip[4], unsigned interface_index,
                                     uint8_t result[6]) {
    const uint8_t *bytes = buffer;
    size_t offset = 0;
    int found = 0;
    if (!bytes || !ip || !result || !interface_index) return 0;
    while (offset < size) {
        if (size - offset < NW_ROUTE_HEADER_SIZE) return 0;
        const uint8_t *message = bytes + offset;
        uint16_t length, index;
        uint32_t addresses;
        memcpy(&length, message, 2); memcpy(&index, message + 4, 2);
        memcpy(&addresses, message + 12, 4);
        if (length < NW_ROUTE_HEADER_SIZE || length > size - offset || message[2] != 5) return 0;
        const uint8_t *values[8] = {0};
        size_t cursor = NW_ROUTE_HEADER_SIZE;
        for (unsigned i = 0; i < 8; ++i) {
            if (!(addresses & (1u << i))) continue;
            if (length - cursor < 2) return 0;
            unsigned count = message[cursor];
            size_t advance = count ? (count + 3u) & ~3u : 4u;
            if (count == 1 || advance > length - cursor) return 0;
            values[i] = message + cursor; cursor += advance;
        }
        const uint8_t *dst = values[0], *link = values[1];
        if (index == interface_index && dst && dst[0] >= 16 && dst[1] == 2 &&
                !memcmp(dst + 4, ip, 4) && link && link[0] >= 8 && link[1] == 18 &&
                link[6] == 6 && 8u + link[5] + 6u <= link[0]) {
            const uint8_t *mac = link + 8 + link[5];
            unsigned nonzero = 0;
            for (unsigned i = 0; i < 6; ++i) nonzero |= mac[i];
            if ((mac[0] & 1) || !nonzero) return 0;
            if (found && memcmp(result, mac, 6)) return 0;
            memcpy(result, mac, 6); found = 1;
        }
        offset += length;
    }
    return found;
}
#endif
