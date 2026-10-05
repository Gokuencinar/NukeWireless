#ifndef NW_DEVICE_CATALOG_H
#define NW_DEVICE_CATALOG_H
#include <stddef.h>

// Display-only model names. No manufacturer IDs, advertising data or radio API.
#define NW_CATALOG_MODELS 6
#define NW_CATALOG_SELECTION 3
#define NW_CATALOG_COMBINATIONS 20
static inline const char *NWCatalogModel(unsigned platform, unsigned model) {
    static const char *const names[3][NW_CATALOG_MODELS] = {
        {"AirPods", "AirPods 2", "AirPods Pro", "AirPods Pro 2", "AirPods Max", "AirPods 4"},
        {"Pixel Buds", "Pixel Buds A-Series", "Pixel Buds Pro", "Pixel Buds Pro 2", "Nest Mini", "Nest Audio"},
        {"Surface Keyboard", "Surface Mouse", "Surface Precision Mouse", "Surface Headphones", "Surface Headphones 2", "Xbox Wireless Controller"}
    };
    return platform < 3 && model < NW_CATALOG_MODELS ? names[platform][model] : NULL;
}
static inline int NWCatalogCombination(unsigned rank, unsigned selected[NW_CATALOG_SELECTION]) {
    if (!selected || rank >= NW_CATALOG_COMBINATIONS) return 0;
    unsigned current = 0;
    for (unsigned a = 0; a < NW_CATALOG_MODELS - 2; ++a)
        for (unsigned b = a + 1; b < NW_CATALOG_MODELS - 1; ++b)
            for (unsigned c = b + 1; c < NW_CATALOG_MODELS; ++c)
                if (current++ == rank) {
                    selected[0] = a; selected[1] = b; selected[2] = c; return 1;
                }
    return 0;
}
// Candidate is sampled uniformly from 19 choices after the first generation.
static inline unsigned NWCatalogNextRank(unsigned candidate, int previous) {
    if (previous >= 0 && previous < NW_CATALOG_COMBINATIONS && candidate >= (unsigned)previous)
        return candidate + 1;
    return candidate;
}
#endif
