#pragma once

// Diagnostics without artificial constraints. Shared by UIKit and the privileged transport.
#define NWBT_DEFAULT_COUNT 5
#define NWBT_DEFAULT_INTERVAL 1
#define NWBT_DEFAULT_INTERVAL_MS 1000

static inline int NWBTPingOptionsValid(unsigned long count, unsigned long interval) {
    return count >= 1 && interval >= 1;
}

static inline int NWBTPingMillisecondsValid(unsigned long count, unsigned long intervalMS) {
    return count >= 1 && intervalMS >= 1;
}
