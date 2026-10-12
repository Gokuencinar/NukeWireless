#ifndef NWBT_SERVICE_H
#define NWBT_SERVICE_H
#include <string.h>
#include <limits.h>

// UART owns its port through the kernel control socket, not by removing the
// daemon that initialized the chip. Skywalk retains its retirement contract.
enum NWBTRecoveryAction { NWBTRecoveryNone, NWBTRecoveryObserve,
    NWBTRecoveryRestore, NWBTRecoveryRetireAndRestore };
static inline enum NWBTRecoveryAction NWBTRecoveryDecision(char arm, int received, char completion) {
    if (arm == 'u') return received == 1 && completion == 'p' ?
        NWBTRecoveryObserve : NWBTRecoveryRetireAndRestore;
    return arm == 'a' ? NWBTRecoveryRestore : NWBTRecoveryNone;
}
// Parse only a unique, complete launchctl PID line. A PID is used for comparing
// snapshots, never for signalling a process.
static inline int NWBTServicePID(const char *state) {
    if (!state || strlen(state) > 65536) return 0;
    const char *line = strstr(state, "\n\tpid = ");
    if (!line || strstr(line + 1, "\n\tpid = ")) return 0;
    const char *p = line + 8;
    int pid = 0;
    if (*p < '1' || *p > '9') return 0;
    do {
        int digit = *p++ - '0';
        if (pid > (INT_MAX - digit) / 10) return 0;
        pid = pid * 10 + digit;
    } while (*p >= '0' && *p <= '9');
    return *p == '\n' && pid > 1 ? pid : 0;
}

// Only these two exact launchd domains may be used or inherited by recovery.
// No caller-supplied service label or path is passed to privileged launchctl.
static inline int NWBTServiceDomainIndex(const char *domain) {
    if (!domain) return -1;
    if (!strcmp(domain, "user/501")) return 0;
    if (!strcmp(domain, "system")) return 1;
    return -1;
}
static inline const char *NWBTServiceDomain(unsigned index) {
    return index == 0 ? "user/501" : index == 1 ? "system" : NULL;
}
static inline const char *NWBTServiceLabel(unsigned index) {
    return index == 0 ? "user/501/com.apple.bluetoothd" :
        index == 1 ? "system/com.apple.bluetoothd" : NULL;
}
#endif
