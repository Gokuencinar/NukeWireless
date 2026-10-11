#include "../src/bluetooth/NWBTH4.h"
#include <assert.h>
#include <stdio.h>
typedef struct { uint8_t bytes[2048]; size_t size, count; } Output;
static void event(const uint8_t *bytes, size_t size, void *context) {
    Output *out = context;
    assert(out->size + size <= sizeof(out->bytes));
    memcpy(out->bytes + out->size, bytes, size); out->size += size; out->count++;
}
int main(void) {
    // Payload contains 0x04,0x0e (event-looking bytes) in an ACL packet.
    const uint8_t stream[] = {4,14,4,1,1,16,0, 2,0,0,3,0,4,14,0, 3,0,0,1,4, 5,0,0,1,0,4, 4,15,4,0,1,1,16};
    const uint8_t expected[] = {14,4,1,1,16,0, 15,4,0,1,1,16};
    for (size_t split = 0; split <= sizeof(stream); split++) {
        NWBTH4Parser parser = {0}; Output out = {0};
        assert(NWBTH4Feed(&parser,stream,split,event,&out));
        assert(NWBTH4Feed(&parser,stream+split,sizeof(stream)-split,event,&out));
        assert(out.count == 2 && out.size == sizeof(expected));
        assert(!memcmp(out.bytes,expected,sizeof(expected)));
        assert(parser.used == 0 && parser.ignored == 3 && parser.frames == 5);
    }
    NWBTH4Parser parser = {0}; Output out = {0};
    for (size_t i=0;i<sizeof(stream);i++) assert(NWBTH4Feed(&parser,stream+i,1,event,&out));
    assert(out.count == 2 && !memcmp(out.bytes,expected,sizeof(expected)));
    const uint8_t unknown[] = {7,4,14,0};
    parser=(NWBTH4Parser){0};
    assert(!NWBTH4Feed(&parser,unknown,sizeof(unknown),NULL,NULL));
    assert(!NWBTH4Feed(&parser,stream,sizeof(stream),NULL,NULL)); // latched, no resync
    const uint8_t oversize[] = {2,0,0,0xff,0xff};
    parser=(NWBTH4Parser){0};
    assert(!NWBTH4Feed(&parser,oversize,sizeof(oversize),NULL,NULL));
    const uint8_t empty[] = {4,0x10,0};
    parser=(NWBTH4Parser){0};
    for (int i=0;i<256;i++) assert(NWBTH4Feed(&parser,empty,sizeof(empty),NULL,NULL));
    assert(!NWBTH4Feed(&parser,empty,sizeof(empty),NULL,NULL));
    parser=(NWBTH4Parser){0}; parser.bytes=65535;
    assert(!NWBTH4Feed(&parser,stream,2,NULL,NULL));
    parser=(NWBTH4Parser){0};
    assert(NWBTH4Feed(&parser,stream,2,NULL,NULL) && parser.used == 2);
    puts("H4 fragmentation, coalescing, data isolation and bounds passed");
    return 0;
}
