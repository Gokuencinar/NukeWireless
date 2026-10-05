#pragma once
#include <stdint.h>
#include <stdbool.h>
typedef enum { NWIdle, NWStarting, NWScanning, NWComplete, NWFailed } NWScanPhase;
typedef struct { uint64_t generation; NWScanPhase phase; double started, progress; } NWScanState;
bool NWStateBusy(const NWScanState *state);
uint64_t NWStateBegin(NWScanState *state, double now);
bool NWStateAccepts(const NWScanState *state, uint64_t generation);
bool NWStateFinish(NWScanState *state, uint64_t generation, bool success);
bool NWStateExpired(const NWScanState *state, double now);
bool NWScanInterfaceReady(uint32_t local, uint32_t mask);
bool NWScanRetryAllowed(const NWScanState *state, double now, unsigned retries, unsigned rows, bool queueIdle);
bool NWScanEmptyQueueExpired(const NWScanState *state, double now, bool startReturned, bool queueIdle, unsigned peers);
bool NWEligibleAddress(uint32_t ip, uint32_t local, uint32_t mask, uint32_t gateway, const uint8_t mac[6]);
double NWPacketInterval(double value);
