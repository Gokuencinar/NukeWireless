#include "../src/bluetooth/NWBTLab.h"
#include "../src/bluetooth/NWBTHCIRead.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t p[25], data[35], enable[6];
    NWBTLabParameters(p);
    assert(p[0]==NWBT_LAB_HANDLE && p[1]==0x10 && p[2]==0);
    assert((p[3] | p[4]<<8 | p[5]<<16)==1600 && p[9]==7 && p[10]==0 && p[19]==20);
    size_t n; uint8_t original[35];
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
            assert(data[offset+4]==0x92 && data[offset+5]==0xbb && data[offset+6]==0xbd);
        }
        offset+=data[offset]+1;
    }
    assert(services==1);
    uint8_t googleCopy[35]; memcpy(googleCopy,data,sizeof data);
    assert(NWBTLabFastPairData(data)==18 && !memcmp(data,googleCopy,sizeof data));
    const int powers[]={-127,-12,0,8,12,20};
    for(unsigned i=0;i<sizeof powers/sizeof powers[0];i++) {
        NWBTLabFastPairData(data);
        assert(NWBTLabFastPairPower(data,powers[i])==21 && data[3]==17);
        assert(data[18]==2 && data[19]==0x0a && (int8_t)data[20]==powers[i]);
        assert(!memcmp(data+4,googleCopy+4,14));
        for(size_t offset=4;offset<21;) { assert(data[offset]>0 && offset+data[offset]+1<=21); offset+=data[offset]+1; }
    }
    NWBTLabFastPairData(data);memcpy(original,data,sizeof data);
    assert(!NWBTLabFastPairPower(data,-128) && !NWBTLabFastPairPower(data,127));
    assert(!memcmp(original,data,sizeof data));
    uint8_t addr[3][7];
    for(unsigned platform=1;platform<=3;platform++) {
        for(unsigned model=0;model<3;model++) {
            n=NWBTLabMultiDeviceData(data,platform,model);assert(n>4 && n<=35 && (size_t)data[3]+4==n && data[0]==NWBT_LAB_MULTI_HANDLE+model && data[0]<=0xef);
            for(size_t offset=4;offset<n;) { assert(data[offset]>0 && offset+data[offset]+1<=n); offset+=data[offset]+1; }
            assert(NWBTLabDeviceAddress(addr[model],platform,model)==7 && (addr[model][6]&0xc0)==0xc0);
            if(platform==2) { const uint16_t ids[]={0x200e,0x2014,0x200a};assert((data[11] | data[12]<<8)==ids[model]); }
            if(platform==3) { const uint8_t ids[][3]={{0x92,0xbb,0xbd},{0x8b,0x66,0xab},{0x01,0xee,0xb4}};assert(!memcmp(data+15,ids[model],3)); }
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
