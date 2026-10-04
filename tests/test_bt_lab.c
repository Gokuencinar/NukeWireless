#include "../src/bluetooth/NWBTLab.h"
#include "../src/bluetooth/NWBTHCIRead.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t p[25], data[35], enable[6];
    NWBTLabParameters(p);
    assert(p[0]==NWBT_LAB_HANDLE && p[1]==0x10 && p[2]==0);
    assert((p[3] | p[4]<<8 | p[5]<<16)==1600 && p[9]==7 && p[10]==0 && p[19]==0);
    size_t n=NWBTLabData(data); assert(n==32 && data[3]==28);
    for (size_t offset=4; offset<n;) { assert(data[offset]>0 && offset+data[offset]+1<=n); offset+=data[offset]+1; }
    n=NWBTLabManufacturerData(data); assert(n==35 && data[3]==31);
    unsigned manufacturers=0, names=0;
    for (size_t offset=4; offset<n;) {
        assert(data[offset]>0 && offset+data[offset]+1<=n);
        if (data[offset+1]==0xff) {
            manufacturers++;
            assert(data[offset]==9 && data[offset+2]==0xff && data[offset+3]==0xff);
            assert(!memcmp(data+offset+4,"NWLab\1",6));
        }
        if (data[offset+1]==9) names++;
        offset+=data[offset]+1;
    }
    assert(manufacturers==1 && names==0);
    NWBTLabEnable(enable,1);assert(enable[0]==1 && enable[1]==1 && enable[2]==NWBT_LAB_HANDLE && (enable[3] | enable[4]<<8)==1000);
    NWBTLabEnable(enable,0);assert(enable[0]==0 && enable[3]==0 && enable[4]==0);
    assert(NWBTLabReplySize(0x0405)==0 && NWBTLabReplySize(0x2008)==0 && NWBTLabReplySize(0xfc00)==0);
    uint8_t credits=0,status=0, reply[]={0x0e,5,1,0x36,0x20,0,0};
    assert(NWBTMatchSizedReply(reply,7,0x2036,NWBTLabReplySize(0x2036),&credits,&status)==1);
    assert(NWBTMatchSizedReply(reply,7,0x2039,NWBTLabReplySize(0x2039),&credits,&status)==0);
    reply[1]=4;assert(NWBTMatchSizedReply(reply,6,0x2036,NWBTLabReplySize(0x2036),&credits,&status)==-1);
    puts("PASS: lab advertisement framing, nonconnectable properties, finite controller duration and replies");
}
