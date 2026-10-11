#ifndef NW_BT_H4_H
#define NW_BT_H4_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Incremental Bluetooth H4 receiver. Events leave this boundary without their
// type byte, matching the existing Skywalk HCI consumer. Known data packets are
// consumed whole, never searched for event-looking bytes inside their payload.
typedef struct {
    uint8_t frame[4096];
    size_t used, needed, bytes, frames, events, ignored;
    int failed;
} NWBTH4Parser;
typedef void (*NWBTH4Event)(const uint8_t *, size_t, void *);
static inline int NWBTH4Feed(NWBTH4Parser *p, const uint8_t *data, size_t length,
                            NWBTH4Event event, void *context) {
    if (p->failed || length > 65536 - p->bytes) { p->failed = 1; return 0; }
    p->bytes += length;
    for (size_t i = 0; i < length; ++i) {
        if (!p->used) {
            switch (data[i]) {
                case 4: p->needed = 3; break; // event
                case 2: case 5: p->needed = 5; break; // ACL / ISO
                case 3: p->needed = 4; break; // SCO
                default: p->failed = 1; return 0;
            }
        }
        p->frame[p->used++] = data[i];
        if (p->used != p->needed) continue;
        size_t header = p->frame[0] == 4 ? 3 : p->frame[0] == 3 ? 4 : 5;
        if (p->used == header) {
            size_t payload = p->frame[header - 1];
            if (header == 5) {
                payload = p->frame[3] | (size_t)p->frame[4] << 8;
                if (p->frame[0] == 5) payload &= 0x3fff;
            }
            if (payload > sizeof(p->frame) - header) { p->failed = 1; return 0; }
            p->needed = header + payload;
            if (payload) continue;
        }
        if (++p->frames > 256) { p->failed = 1; return 0; }
        if (p->frame[0] == 4) {
            ++p->events;
            if (event) event(p->frame + 1, p->used - 1, context);
        } else ++p->ignored;
        p->used = p->needed = 0;
    }
    return 1;
}
#endif
