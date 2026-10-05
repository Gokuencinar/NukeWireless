#include "../src/bluetooth/NWBTLab.h"
#include "../src/bluetooth/NWBTHCIRead.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t p[25], data[35], enable[6];
    NWBTLabParameters(p);
    assert(p[0]==NWBT_LAB_HANDLE && p[1]==0x10 && p[2]==0);
    assert((p[3] | p[4]<<8 | p[5]<<16)==1600 && p[9]==7 && p[10]==0 && p[19]==20);
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
    for (unsigned sequence=0; sequence<NWBT_LAB_ROTATION_COUNT; ++sequence) {
        n=NWBTLabRotatingData(data,sequence);
        assert(n==35 && data[3]==31 && data[9]==0x22);
        assert(data[25]==9 && data[26]==0xff && data[27]==0xff && data[28]==0xff);
        assert(!memcmp(data+29,"NWRo\1",5) && data[34]==sequence);
        for (size_t offset=4; offset<n;) {
            assert(data[offset]>0 && offset+data[offset]+1<=n);
            offset+=data[offset]+1;
        }
    }
    uint8_t original[35];memcpy(original,data,sizeof data);
    assert(NWBTLabRotatingData(data,NWBT_LAB_ROTATION_COUNT)==0);
    assert(NWBTLabRotatingData(data,~0u)==0 && !memcmp(data,original,sizeof data));
    NWBTLabSwiftPairParameters(p);
    assert(p[1]==0x10 && p[2]==0 && p[10]==0); // No connection or identity rotation.
    assert((p[3] | p[4]<<8 | p[5]<<16)==244 && !memcmp(p+3,p+6,3));
    n=NWBTLabSwiftPairData(data);
    assert(n==19 && data[3]==15 && data[0]==NWBT_LAB_HANDLE);
    unsigned swiftSections=0;
    for (size_t offset=4; offset<n;) {
        assert(data[offset]>0 && offset+data[offset]+1<=n);
        if (data[offset+1]==0xff) {
            swiftSections++;
            assert(data[offset]==11 && data[offset+2]==6 && data[offset+3]==0);
            assert(data[offset+4]==3 && data[offset+5]==0 && data[offset+6]==0x80);
            assert(!memcmp(data+offset+7,"NWLab",5));
        }
        offset+=data[offset]+1;
    }
    assert(swiftSections==1);
    n=NWBTLabApplePairingData(data);
    assert(n==35 && data[3]==31 && data[0]==NWBT_LAB_HANDLE);
    // Exactly one well-formed manufacturer section fills the legacy AD budget.
    assert(data[4]+1==31 && data[5]==0xff && data[6]==0x4c && data[7]==0);
    assert(data[8]==7 && data[9]==25 && (size_t)data[9]+10==n);
    assert(data[10]==7 && (data[11] | data[12]<<8)==0x200e);
    uint8_t appleCopy[35]; memcpy(appleCopy,data,sizeof data);
    assert(NWBTLabApplePairingData(data)==35 && !memcmp(data,appleCopy,sizeof data));
    NWBTLabFastPairParameters(p);
    assert(p[1]==0x10 && p[2]==0 && p[10]==0 && p[19]==20);
    assert((p[3] | p[4]<<8 | p[5]<<16)==160 && !memcmp(p+3,p+6,3));
    n=NWBTLabFastPairData(data); assert(n==18 && data[3]==14);
    unsigned services=0;
    for (size_t offset=4; offset<n;) {
        assert(data[offset]>0 && offset+data[offset]+1<=n && data[offset+1]!=0xff);
        if (data[offset+1]==0x16) {
            services++;
            assert(data[offset]==6 && data[offset+2]==0x2c && data[offset+3]==0xfe);
            assert(data[offset+4]==0xcd && data[offset+5]==0x82 && data[offset+6]==0x56);
        }
        offset+=data[offset]+1;
    }
    assert(services==1);
    uint8_t googleCopy[35]; memcpy(googleCopy,data,sizeof data);
    assert(NWBTLabFastPairData(data)==18 && !memcmp(data,googleCopy,sizeof data));
    uint8_t addr[3][7];
    for(unsigned platform=1;platform<=3;platform++) {
        for(unsigned model=0;model<3;model++) {
            n=NWBTLabMultiDeviceData(data,platform,model);assert(n>4 && n<=35 && (size_t)data[3]+4==n && data[0]==NWBT_LAB_MULTI_HANDLE+model && data[0]<=0xef);
            for(size_t offset=4;offset<n;) { assert(data[offset]>0 && offset+data[offset]+1<=n); offset+=data[offset]+1; }
            assert(NWBTLabDeviceAddress(addr[model],platform,model)==7 && (addr[model][6]&0xc0)==0xc0);
            if(platform==2) { const uint16_t ids[]={0x200e,0x2014,0x200a};assert((data[11] | data[12]<<8)==ids[model]); }
            if(platform==3) { const uint8_t ids[][3]={{0xcd,0x82,0x56},{0,0,0x47},{0x14,0,0x45}};assert(!memcmp(data+15,ids[model],3)); }
        }
        assert(memcmp(addr[0]+1,addr[1]+1,6) && memcmp(addr[1]+1,addr[2]+1,6));
    }
    assert(!NWBTLabMultiDeviceData(data,0,0) && !NWBTLabMultiDeviceData(data,1,3));
    assert(!NWBTLabDeviceAddress(addr[0],4,0));
    uint8_t multiple[6];
    for(unsigned i=0;i<3;i++) {
        assert(NWBTLabDeviceEnable(multiple,1,i)==6 && multiple[0]==1 && multiple[1]==1);
        assert(multiple[2]==NWBT_LAB_MULTI_HANDLE+i && multiple[2]<=0xef && (multiple[3] | multiple[4]<<8)==1000 && multiple[5]==0);
        assert(NWBTLabDeviceEnable(multiple,0,i)==6 && multiple[0]==0 && multiple[3]==0 && multiple[4]==0);
    }
    assert(NWBTLabDeviceEnable(multiple,1,3)==0);
    assert(NWBTLabReplySize(0x203b)==2 && NWBTLabReplySize(0x203a)==0);
    NWBTLabEnable(enable,1);assert(enable[0]==1 && enable[1]==1 && enable[2]==NWBT_LAB_HANDLE && (enable[3] | enable[4]<<8)==1000);
    NWBTLabEnable(enable,0);assert(enable[0]==0 && enable[3]==0 && enable[4]==0);
    assert(NWBTLabReplySize(0x0405)==0 && NWBTLabReplySize(0x2008)==0 && NWBTLabReplySize(0xfc00)==0);
    uint8_t credits=0,status=0, reply[]={0x0e,5,1,0x36,0x20,0,0};
    assert(NWBTMatchSizedReply(reply,7,0x2036,NWBTLabReplySize(0x2036),&credits,&status)==1);
    assert(NWBTMatchSizedReply(reply,7,0x2039,NWBTLabReplySize(0x2039),&credits,&status)==0);
    reply[1]=4;assert(NWBTMatchSizedReply(reply,6,0x2036,NWBTLabReplySize(0x2036),&credits,&status)==-1);
    puts("PASS: lab advertisement framing, nonconnectable properties, finite controller duration and replies");
}
