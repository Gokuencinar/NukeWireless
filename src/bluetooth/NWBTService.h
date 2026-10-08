#ifndef NWBT_SERVICE_H
#define NWBT_SERVICE_H
#include <string.h>

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
