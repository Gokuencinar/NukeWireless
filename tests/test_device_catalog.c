#include "../src/NWDeviceCatalog.h"
#include <assert.h>
#include <string.h>
int main(void) {
    unsigned seen[64] = {0};
    for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
        unsigned selected[3]; assert(NWCatalogCombination(rank, selected));
        assert(selected[0] < selected[1] && selected[1] < selected[2] && selected[2] < 6);
        unsigned mask = (1u << selected[0]) | (1u << selected[1]) | (1u << selected[2]);
        assert(!seen[mask]); seen[mask] = 1;
        for (unsigned platform = 0; platform < 3; ++platform)
            for (unsigned slot = 0; slot < 3; ++slot) assert(strlen(NWCatalogModel(platform, selected[slot])));
        unsigned ranks[20] = {0};
        for (unsigned candidate = 0; candidate < 19; ++candidate) {
            unsigned next = NWCatalogNextRank(candidate, (int)rank);
            assert(next < 20 && next != rank && !ranks[next]); ranks[next] = 1;
        }
    }
    unsigned sentinel[3] = {7,8,9};
    assert(!NWCatalogCombination(20, sentinel) && sentinel[0] == 7 && sentinel[1] == 8 && sentinel[2] == 9);
    assert(!NWCatalogCombination(0, NULL));
    assert(!NWCatalogModel(3, 0) && !NWCatalogModel(0, 6));
    for (unsigned rank = 0; rank < 20; ++rank) assert(NWCatalogNextRank(rank, -1) == rank);
    return 0;
}
