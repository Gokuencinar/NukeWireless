#include "../src/NWARPBinding.h"
#include "../src/NWCompatibility.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint8_t target[6], router[6], phone[6], changed[6];
    assert(NWARPParseMAC("02:11:22:33:44:55", target));
    assert(NWARPParseMAC("00:11:22:33:44:66", router));
    assert(NWARPParseMAC("00:11:22:33:44:77", phone));
    assert(NWARPParseMAC("02:11:22:33:44:88", changed));
    assert(!NWARPParseMAC("00:00:00:00:00:00", changed));
    assert(!NWARPParseMAC("01:11:22:33:44:55", changed));
    assert(!NWARPParseMAC("02:11:22:33:44:5g", changed));
    assert(!NWARPParseMAC("2:11:22:33:44:55", changed));
    uint32_t local=0xc0a80116, gateway=0xc0a80101, peer=0xc0a80130, mask=0xffffff00;
    assert(!NWARPBindingError(peer,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(gateway,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(local,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(0xc0a801ff,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(0xc0a80100,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(0xc0a80230,local,mask,gateway,target,target,router,phone));
    assert(NWARPBindingError(peer,local,mask,0,target,target,router,phone));
    assert(NWARPParseMAC("02:11:22:33:44:88", changed));
    assert(NWARPBindingError(peer,local,mask,gateway,target,changed,router,phone));
    assert(NWARPBindingError(peer,local,mask,gateway,router,router,router,phone));
    assert(NWARPBindingError(peer,local,mask,gateway,phone,phone,router,phone));
    for(unsigned ios=0;ios<30;++ios) for(unsigned darwin=0;darwin<33;++darwin)
        assert(NWTransportOSContract(ios,darwin)==((ios>=15 && ios<=18 && darwin==ios+6)||(ios==26 && darwin==25)));
    assert(NWPFKernelContract(25) && !NWPFKernelContract(26) && !NWPFKernelContract(20));
    puts("PASS: current single-peer binding, changed/shared identities and explicit iOS 26/Darwin 25 admission");
}
