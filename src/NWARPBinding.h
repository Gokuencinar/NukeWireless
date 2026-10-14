#ifndef NW_ARP_BINDING_H
#define NW_ARP_BINDING_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
static inline int NWARPParseMAC(const char *text, uint8_t mac[6]) {
    if (!text || strlen(text) != 17) return 0;
    for (unsigned i = 0; i < 6; ++i) {
        unsigned value = 0;
        for (unsigned j = 0; j < 2; ++j) {
            unsigned char c = (unsigned char)text[i * 3 + j];
            unsigned n = c >= '0' && c <= '9' ? c - '0' :
                c >= 'a' && c <= 'f' ? c - 'a' + 10 :
                c >= 'A' && c <= 'F' ? c - 'A' + 10 : 16;
            if (n > 15) return 0;
            value = value * 16 + n;
        }
        mac[i] = (uint8_t)value;
        if (i < 5 && text[i * 3 + 2] != ':') return 0;
    }
    uint8_t any = 0; for (unsigned i = 0; i < 6; ++i) any |= mac[i];
    return any && !(mac[0] & 1);
}
// All IPv4 values are host order. Binding is to one current en0 neighbour;
// duplicate identities, gateway/local/network/broadcast targets fail closed.
static inline const char *NWARPBindingError(uint32_t peer, uint32_t local,
    uint32_t mask, uint32_t gateway, const uint8_t target[6],
    const uint8_t observed[6], const uint8_t router[6], const uint8_t phone[6]) {
    uint32_t host = ~mask;
    if (!local || !gateway || !mask || host < 3 || (host & (host + 1))) return "network_unavailable";
    if (!peer || peer == local || peer == gateway || (peer >> 24) == 127 || (peer >> 28) >= 14 ||
        (peer & mask) != (local & mask) || (gateway & mask) != (local & mask) ||
        !(peer & host) || (peer & host) == host) return "ineligible_target";
    if (!target || !observed || !router || !phone) return "identity_unavailable";
    if (memcmp(target, observed, 6)) return "neighbor_identity_changed";
    if (!memcmp(target, router, 6) || !memcmp(target, phone, 6) || !memcmp(router, phone, 6)) return "shared_link_identity";
    return NULL;
}
#endif
