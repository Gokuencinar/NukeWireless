#include "../src/NWDeviceCatalog.h"
#include <assert.h>
#include <string.h>
int main(void) {
    unsigned seen[1 << NW_CATALOG_MODELS] = {0};
    for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
        unsigned selected[NW_CATALOG_SELECTION]; assert(NWCatalogCombination(rank, selected));
        unsigned mask = 0;
        for (unsigned slot = 0; slot < NW_CATALOG_SELECTION; ++slot) {
            assert(selected[slot] < NW_CATALOG_MODELS);
            if (slot) assert(selected[slot - 1] < selected[slot]);
            mask |= 1u << selected[slot];
        }
        assert(!seen[mask]); seen[mask] = 1;
        for (unsigned platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform)
            for (unsigned slot = 0; slot < NW_CATALOG_SELECTION; ++slot) {
                const char *name = NWCatalogModel(platform, selected[slot]);
                if (platform == 1 || selected[slot] < 9) assert(name && strlen(name));
                else assert(!name);
            }
        unsigned ranks[NW_CATALOG_COMBINATIONS] = {0};
        for (unsigned candidate = 0; candidate < NW_CATALOG_COMBINATIONS - 1; ++candidate) {
            unsigned next = NWCatalogNextRank(candidate, (int)rank);
            assert(next < NW_CATALOG_COMBINATIONS && next != rank && !ranks[next]); ranks[next] = 1;
        }
    }
    unsigned sentinel[NW_CATALOG_SELECTION] = {9,9,9,9,9,9};
    assert(!NWCatalogCombination(NW_CATALOG_COMBINATIONS, sentinel));
    for (unsigned slot = 0; slot < NW_CATALOG_SELECTION; ++slot) assert(sentinel[slot] == 9);
    assert(!NWCatalogCombination(0, NULL));
    assert(!NWCatalogModel(NW_CATALOG_PLATFORMS, 0) && !NWCatalogModel(0, NW_CATALOG_MODELS));
    for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) assert(NWCatalogNextRank(rank, -1) == rank);
    return 0;
}
