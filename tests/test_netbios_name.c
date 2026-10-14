#include "../src/NWNetBIOSName.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t request[50], response[12+34+10+1+36+46] = {0}; char name[16];
    NWNBStatusRequest(request,0x1234);
    assert(NWNBWord(request)==0x1234 && NWNBWord(request+4)==1);
    assert(request[12]==32 && request[13]=='C' && request[14]=='K' && request[15]=='A');
    assert(request[45]==0 && NWNBWord(request+46)==0x21 && NWNBWord(request+48)==1);
    memcpy(response,request,46); response[2]=0x84; response[5]=0; response[7]=1;
    response[47]=0x21; response[49]=1; response[55]=83; response[56]=2;
    memcpy(response+57,"WORKGROUP      ",15); response[73]=0x80;
    memcpy(response+75,"OFFICE-PC      ",15); response[91]=0x04;
    assert(NWNBStatusName(response,sizeof(response),0x1234,name) && !strcmp(name,"OFFICE-PC"));
    for (size_t i=0;i<sizeof(response);i++) assert(!NWNBStatusName(response,i,0x1234,name));
    assert(!NWNBStatusName(response,sizeof(response),0x4321,name));
    response[91]=0x84; assert(!NWNBStatusName(response,sizeof(response),0x1234,name)); response[91]=0x04;
    response[90]=0x20; assert(NWNBStatusName(response,sizeof(response),0x1234,name));
    response[90]=0x03; assert(!NWNBStatusName(response,sizeof(response),0x1234,name)); response[90]=0;
    response[75]=1; assert(!NWNBStatusName(response,sizeof(response),0x1234,name)); response[75]='O';
    response[55]=255; assert(!NWNBStatusName(response,sizeof(response),0x1234,name)); response[55]=83;
    response[56]=64; assert(!NWNBStatusName(response,sizeof(response),0x1234,name)); response[56]=2;
    // Question + compressed answer name, as used by Windows/Samba responders.
    uint8_t compressed[50+2+10+1+36+46]={0};
    memcpy(compressed,request,50); compressed[2]=0x84; compressed[7]=1;
    compressed[50]=0xc0; compressed[51]=12; memcpy(compressed+52,response+46,sizeof(response)-46);
    assert(NWNBStatusName(compressed,sizeof(compressed),0x1234,name));
    compressed[51]=50; assert(!NWNBStatusName(compressed,sizeof(compressed),0x1234,name));
    uint8_t fuzz[4096]; uint32_t seed=1;
    for (unsigned i=0;i<10000;i++) {
        size_t size=i%sizeof(fuzz);
        for (size_t j=0;j<size;j++) { seed=seed*1664525+1013904223; fuzz[j]=(uint8_t)(seed>>24); }
        (void)NWNBStatusName(fuzz,size,0x1234,name);
    }
    puts("NBSTAT: request, unique names, groups, suffixes, truncation, lengths, compressed names, transaction and random inputs passed");
    return 0;
}
