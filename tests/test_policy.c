#include "../src/NWPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    NWScanState state = {0};
    assert(!NWStateBusy(&state));
    uint64_t first = NWStateBegin(&state, 10);
    assert(NWStateBusy(&state)); assert(!NWStateExpired(&state,14)); assert(NWStateExpired(&state,16));
    assert(NWStateFinish(&state,first,false)); assert(!NWStateBusy(&state));
    uint64_t second = NWStateBegin(&state,20);
    assert(second != first); assert(!NWStateAccepts(&state,first));
    assert(!NWStateFinish(&state,first,true)); assert(NWStateBusy(&state));
    state.phase=NWScanning; state.progress=40;
    assert(!NWStateExpired(&state,60)); assert(NWStateExpired(&state,86));
    state.progress=400; assert(NWStateExpired(&state,400)); // absolute cap despite ongoing callbacks
    assert(NWStateFinish(&state,second,true)); assert(!NWStateAccepts(&state,second));
    for(int i=0;i<1000;i++) { uint64_t g=NWStateBegin(&state, i); state.phase=NWScanning; assert(NWStateFinish(&state,g,i%2)); }
    const uint8_t mac[6]={0x02,0x12,0x34,0x56,0x78,0x90};
    const uint8_t multicast[6]={0x01,0,0,0,0,1}, zero[6]={0};
    uint32_t local=0xc0a80112, gateway=0xc0a80101, mask=0xffffff00, target=0xc0a80120;
    assert(NWEligibleAddress(target,local,mask,gateway,mac)); // randomized unicast MAC is valid
    assert(!NWEligibleAddress(local,local,mask,gateway,mac));
    assert(!NWEligibleAddress(gateway,local,mask,gateway,mac));
    assert(!NWEligibleAddress(target,local,mask,0,mac));
    assert(!NWEligibleAddress(target,0,mask,gateway,mac));
    assert(!NWEligibleAddress(0xc0a80220,local,mask,gateway,mac));
    assert(!NWEligibleAddress(0xc0a801ff,local,mask,gateway,mac));
    assert(!NWEligibleAddress(0xc0a80100,local,mask,gateway,mac));
    assert(!NWEligibleAddress(target,local,0xffffff01,gateway,mac));
    assert(!NWEligibleAddress(target,local,mask,gateway,multicast));
    assert(!NWEligibleAddress(target,local,mask,gateway,zero));
    assert(!NWEligibleAddress(0xe0000001,local,mask,gateway,mac));
    assert(NWPacketInterval(0.2)==0.2); assert(NWPacketInterval(5)==5);
    assert(NWPacketInterval(NAN)==0.9); assert(NWPacketInterval(INFINITY)==0.9); assert(NWPacketInterval(-1)==0.9);
    puts("PASS: scan generations, retry, late callbacks, deadlines, target exclusions and interval bounds");
}
