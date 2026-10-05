#include "NWPolicy.h"
#include <math.h>
bool NWStateBusy(const NWScanState *s) { return s->phase == NWStarting || s->phase == NWScanning; }
uint64_t NWStateBegin(NWScanState *s, double now) {
    ++s->generation; s->phase = NWStarting; s->started = s->progress = now;
    return s->generation;
}
bool NWStateAccepts(const NWScanState *s, uint64_t g) { return s->generation == g && NWStateBusy(s); }
bool NWStateFinish(NWScanState *s, uint64_t g, bool success) {
    if (!NWStateAccepts(s, g)) return false;
    s->phase = success ? NWComplete : NWFailed; return true;
}
bool NWStateExpired(const NWScanState *s, double now) {
    if (!NWStateBusy(s)) return false;
    return now - s->started > (s->phase == NWStarting ? 5 : 300) || now - s->progress > 45;
}
bool NWScanInterfaceReady(uint32_t local, uint32_t mask) {
    uint32_t hostmask = ~mask;
    return local && (local >> 24) != 127 && (local >> 16) != 0xa9fe &&
        (local >> 28) < 14 && mask && !(hostmask & (hostmask + 1)) && hostmask >= 3 &&
        (local & hostmask) && (local & hostmask) != hostmask;
}
bool NWScanRetryAllowed(const NWScanState *s, double now, unsigned retries, unsigned rows, bool queueIdle) {
    return !retries && queueIdle && !NWStateBusy(s) &&
        (s->phase == NWFailed || (s->phase == NWComplete && !rows)) && now - s->progress >= 2;
}
bool NWScanEmptyQueueExpired(const NWScanState *s, double now, bool startReturned, bool queueIdle, unsigned peers) {
    return s->phase == NWScanning && startReturned && queueIdle && !peers && now - s->progress >= 5;
}
// Host-order IPv4 values. Fail closed when the current network is unknown.
bool NWEligibleAddress(uint32_t ip, uint32_t local, uint32_t mask, uint32_t gateway, const uint8_t mac[6]) {
    uint32_t hostmask = ~mask;
    if (!local || !gateway || !mask || (hostmask & (hostmask + 1)) || hostmask < 3) return false;
    if (!ip || ip == local || ip == gateway || (ip >> 24) == 127 || (ip >> 28) >= 14) return false;
    if ((ip & mask) != (local & mask) || (gateway & mask) != (local & mask)) return false;
    if (!(ip & hostmask) || (ip & hostmask) == hostmask) return false;
    if (!mac || (mac[0] & 1)) return false;
    uint8_t any = 0; for (int i = 0; i < 6; ++i) any |= mac[i];
    return any != 0;
}
double NWPacketInterval(double value) { return isfinite(value) && value >= 0.2 && value <= 5 ? value : 0.9; }
