#ifndef NWBT_HCI_READ_H
#define NWBT_HCI_READ_H
#include <stdint.h>
#include <stddef.h>

// Fixed read-only allowlist. Sizes include status, exclude the event header,
// command credits and opcode. No vendor command or caller-supplied opcode.
static inline size_t NWBTReadReplySize(uint16_t opcode) {
    switch (opcode) {
        case 0x1001: return 9;
        case 0x1002: return 65;
        case 0x1003: case 0x2003: case 0x201c: return 9;
        default: return 0;
    }
}

// 0 = unrelated; 1 = valid completion; 2 = command status rejection;
// -1 = malformed reply for the pending command. A successful Command Status
// does not replace Command Complete for these synchronous read commands.
static inline int NWBTMatchSizedReply(const uint8_t *p, size_t n, uint16_t opcode, size_t replySize,
                                     uint8_t *credits, uint8_t *status) {
    if (!p || n < 2 || n != (size_t)p[1] + 2) return -1;
    if (p[0] == 0x0e) {
        if (n < 5) return -1;
        *credits = p[2];
        if ((uint16_t)(p[3] | (uint16_t)p[4] << 8) != opcode) return 0;
        if (n < 6) return -1;
        *status = p[5];
        if (*status) return n == 6 || n == 5 + replySize ? 1 : -1;
        return replySize && n == 5 + replySize ? 1 : -1;
    }
    if (p[0] == 0x0f) {
        if (n != 6) return -1;
        *credits = p[3];
        if ((uint16_t)(p[4] | (uint16_t)p[5] << 8) != opcode) return 0;
        *status = p[2];
        return *status ? 2 : 0;
    }
    return 0;
}
static inline int NWBTMatchReadReply(const uint8_t *p, size_t n, uint16_t opcode,
                                     uint8_t *credits, uint8_t *status) {
    size_t size = NWBTReadReplySize(opcode);
    return size ? NWBTMatchSizedReply(p, n, opcode, size, credits, status) : -1;
}
#endif
