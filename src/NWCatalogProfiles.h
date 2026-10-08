#ifndef NW_CATALOG_PROFILES_H
#define NW_CATALOG_PROFILES_H
#include "NWDeviceCatalog.h"
#include <stdint.h>

// Research fixtures, not proof that a receiver displays a pairing notification.
// Apple: esphome-components/examples/ble_gateway/airpods.yaml (2002/200F),
// plus the existing app26 fixtures (200E/2014/200A).
// Google/Samsung: Xtreme-Apps 1e423683, protocols/fastpair.c and easysetup.c.
// Galaxy Buds2 Pro: BLE-Payloads afccfb8, complete manufacturer capture.
static inline uint32_t NWCatalogProfileID(unsigned platform, unsigned model) {
    static const uint32_t ids[NW_CATALOG_PLATFORMS][NW_CATALOG_MODELS] = {
        {0x2002, 0x200f, 0x200e, 0x2014, 0x200a, 0, 0x2013, 0x2011, 0x2012},
        {0x92bbbd, 0x8b66ab, 0x9adb11, 0, 0, 0, 0x058d08, 0xcd8256, 0x821f66, 0xc8d335, 0xd446a7, 0x8b0a91},
        {0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0xb8b905, 0xd30704, 0x850116, 0x3f6718, 0xeaaa17, 0xab0c46, 0x39ea48, 0x011716, 0x42c519}
    };
    return platform < NW_CATALOG_PLATFORMS && model < NW_CATALOG_MODELS ? ids[platform][model] : 0;
}
static inline int NWCatalogProfileAvailable(unsigned platform, unsigned model) {
    // Swift Pair carries a display name, not a registered product/model ID.
    return NWCatalogModel(platform, model) && (platform == 2 || NWCatalogProfileID(platform, model));
}
static inline int NWCatalogProfileSelection(unsigned platform, const unsigned *models, size_t count) {
    if (!models || !count || count > NW_CATALOG_SELECTION) return 0;
    for (size_t i = 0; i < count; ++i) {
        if (!NWCatalogProfileAvailable(platform, models[i])) return 0;
        for (size_t j = 0; j < i; ++j) if (models[i] == models[j]) return 0;
    }
    return 1;
}
// Ordinals refer only to complete six-model selections with known profiles.
// previous is the original catalog rank, so it remains stable per brand.
static inline unsigned NWCatalogProfileRanks(unsigned platform, unsigned ranks[NW_CATALOG_COMBINATIONS]) {
    unsigned count = 0;
    if (!ranks) return 0;
    for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
        unsigned models[NW_CATALOG_SELECTION];
        if (NWCatalogCombination(rank, models) && NWCatalogProfileSelection(platform, models, NW_CATALOG_SELECTION)) ranks[count++] = rank;
    }
    return count;
}
// Strict command-line encoding: 1-6 decimal model indices, comma separated.
// Reject leading zeroes and out-of-range values before arithmetic can overflow.
static inline size_t NWCatalogProfileParse(const char *text, unsigned platform, unsigned models[NW_CATALOG_SELECTION]) {
    if (!text || !models) return 0;
    size_t count = 0;
    while (*text) {
        if (count == NW_CATALOG_SELECTION || *text < '0' || *text > '9') return 0;
        if (*text == '0' && text[1] >= '0' && text[1] <= '9') return 0;
        unsigned model = 0;
        do {
            model = model * 10 + (unsigned)(*text++ - '0');
            if (model >= NW_CATALOG_MODELS) return 0;
        } while (*text >= '0' && *text <= '9');
        models[count++] = model;
        if (!*text) break;
        if (*text++ != ',' || !*text) return 0;
    }
    return NWCatalogProfileSelection(platform, models, count) ? count : 0;
}
#endif
