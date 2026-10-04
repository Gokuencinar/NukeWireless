#pragma once

// Finite diagnostics only. Shared by UIKit and the privileged transport.
#define NWBT_DEFAULT_COUNT 5
#define NWBT_DEFAULT_INTERVAL 1
#define NWBT_MAX_COUNT 20
#define NWBT_MIN_INTERVAL 1
#define NWBT_MAX_INTERVAL 5
#define NWBT_MAX_PING_SECONDS 20

static inline int NWBTPingOptionsValid(unsigned long count, unsigned long interval) {
    return count >= 1 && count <= NWBT_MAX_COUNT &&
        interval >= NWBT_MIN_INTERVAL && interval <= NWBT_MAX_INTERVAL &&
        count * interval <= NWBT_MAX_PING_SECONDS;
}
