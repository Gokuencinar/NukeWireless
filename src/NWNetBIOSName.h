#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// RFC 1002 NBSTAT: wildcard node status, no name registration or session.
static inline void NWNBStatusRequest(uint8_t packet[50], uint16_t transaction) {
    memset(packet, 0, 50);
    packet[0] = transaction >> 8; packet[1] = transaction & 255;
    packet[5] = 1; packet[12] = 32;
    for (unsigned i = 0; i < 16; i++) {
        uint8_t c = i ? 0 : '*';
        packet[13 + 2*i] = 'A' + (c >> 4);
        packet[14 + 2*i] = 'A' + (c & 15);
    }
    packet[47] = 0x21; packet[49] = 1;
}
static inline uint16_t NWNBWord(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
// Validate compressed names without following unbounded pointers.
static inline int NWNBSkipName(const uint8_t *p, size_t n, size_t *offset) {
    size_t cursor = *offset, consumed = 0; unsigned hops = 0;
    while (cursor < n && ++hops <= 128) {
        uint8_t len = p[cursor++];
        if (!len) { *offset = consumed ? consumed : cursor; return 1; }
        if ((len & 0xc0) == 0xc0) {
            if (cursor >= n) return 0;
            size_t target = ((len & 63) << 8) | p[cursor++];
            if (target < 12 || target >= cursor - 2) return 0;
            if (!consumed) consumed = cursor;
            cursor = target;
        } else {
            if (len > 63 || len > n - cursor) return 0;
            cursor += len;
        }
    }
    return 0;
}
static inline int NWNBStatusName(const uint8_t *p, size_t n, uint16_t transaction, char out[16]) {
    if (!p || n < 12 || n > 4096 || NWNBWord(p) != transaction ||
        (NWNBWord(p+2) & 0xfe0f) != 0x8400 || NWNBWord(p+4) > 1 ||
        NWNBWord(p+6) != 1 || NWNBWord(p+8) || NWNBWord(p+10)) return 0;
    size_t off = 12;
    if (NWNBWord(p+4)) {
        if (!NWNBSkipName(p,n,&off) || n-off < 4 || NWNBWord(p+off) != 0x21 || NWNBWord(p+off+2) != 1) return 0;
        off += 4;
    }
    if (!NWNBSkipName(p,n,&off) || n-off < 10 || NWNBWord(p+off) != 0x21 || NWNBWord(p+off+2) != 1) return 0;
    size_t size = NWNBWord(p+off+8); off += 10;
    if (!size || size != n-off) return 0;
    unsigned count = p[off++];
    if (!count || count > 64 || size != 1 + count*18 + 46) return 0;
    for (unsigned i = 0; i < count; i++) {
        const uint8_t *entry = p+off+i*18;
        if ((entry[15] != 0 && entry[15] != 0x20) || (NWNBWord(entry+16) & 0x9800)) continue;
        unsigned length = 15;
        while (length && entry[length-1] == ' ') length--;
        if (!length) continue;
        int valid = 1;
        for (unsigned j = 0; j < length; j++)
            if (entry[j] < 32 || entry[j] > 126 || entry[j] == '<' || entry[j] == '>') valid = 0;
        if (valid) { memcpy(out,entry,length); out[length] = 0; return 1; }
    }
    return 0;
}
