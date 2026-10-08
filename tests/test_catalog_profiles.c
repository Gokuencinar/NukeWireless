#include "../src/bluetooth/NWBTLab.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    const uint32_t apple[] = {0x2002, 0x200f, 0x200e, 0x2014, 0x200a, 0, 0x2013, 0x2011, 0x2012};
    const uint32_t google[] = {0x92bbbd, 0x8b66ab, 0x9adb11, 0, 0, 0, 0x058d08, 0xcd8256, 0x821f66, 0xc8d335, 0xd446a7, 0x8b0a91};
    const uint32_t samsung[] = {0xb8b905, 0xd30704, 0x850116, 0x3f6718, 0xeaaa17, 0xab0c46, 0x39ea48, 0x011716, 0x42c519};
    unsigned available[NW_CATALOG_PLATFORMS] = {0};
    uint8_t addresses[NW_CATALOG_PLATFORMS * NW_CATALOG_MODELS][6]; unsigned addressCount = 0;
    for (unsigned platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        for (unsigned model = 0; model < NW_CATALOG_MODELS; ++model) {
            uint8_t buffer[37]; memset(buffer, 0x5a, sizeof buffer);
            size_t n = NWBTLabCatalogData(buffer + 1, platform, model);
            assert(buffer[0] == 0x5a && buffer[36] == 0x5a);
            if (!NWCatalogProfileAvailable(platform, model)) {
                assert(!n);
                for (size_t i = 0; i < sizeof buffer; ++i) assert(buffer[i] == 0x5a);
                continue;
            }
            available[platform]++;
            uint8_t *data = buffer + 1;
            assert(n <= 35 && n == (size_t)data[3] + 4);
            for (size_t offset = 4; offset < n;) {
                assert(data[offset] && offset + data[offset] + 1 <= n);
                offset += data[offset] + 1;
            }
            if (platform == 0) {
                assert(n == 35 && data[5] == 0xff && data[6] == 0x4c);
                assert(((uint32_t)data[11] | (uint32_t)data[12] << 8) == apple[model]);
            } else if (platform == 1) {
                assert(n == 18 && data[12] == 0x16 && data[13] == 0x2c && data[14] == 0xfe);
                assert(((uint32_t)data[15] << 16 | data[16] << 8 | data[17]) == google[model]);
                assert(NWBTLabFastPairPower(data, -12) == 21 && (int8_t)data[20] == -12);
            } else if (platform == 2) {
                const char *name = NWCatalogModel(platform, model);
                assert(n == 11 + strlen(name) && data[4] == 6 + strlen(name));
                assert(data[5] == 0xff && data[6] == 6 && data[7] == 0 && data[8] == 3 && data[9] == 0 && data[10] == 0x80);
                assert(!memcmp(data + 11, name, strlen(name)));
            } else {
                assert(n == 32 && data[3] == 28 && data[4] == 27);
                assert(data[5] == 0xff && data[6] == 0x75 && data[7] == 0);
                assert(data[8] == 0x42 && data[20] == 1);
                assert(((uint32_t)data[18] << 16 | data[19] << 8 | data[21]) == samsung[model]);
                if (model == 5) {
                    const uint8_t captured[] = {0x42,0x09,0x81,0x02,0x14,0x15,0x03,0x21,0x01,0x09,0xab,0x0c,0x01,0x46,0x06,0x3c,0xdd,0x0a,0,0,0,0,0xa7,0};
                    assert(!memcmp(data + 8, captured, sizeof captured));
                }
            }
            uint8_t first[7], moved[7];
            assert(NWBTLabCatalogAddress(first, platform, model, 0) == 7);
            assert(NWBTLabCatalogAddress(moved, platform, model, 2) == 7);
            assert(first[0] != moved[0] && !memcmp(first + 1, moved + 1, 6));
            assert((first[6] & 0xc0) == 0xc0);
            for (unsigned i = 0; i < addressCount; ++i) assert(memcmp(first + 1, addresses[i], 6));
            memcpy(addresses[addressCount++], first + 1, 6);
        }
    }
    assert(available[0] == 8 && available[1] == 9 && available[2] == 9 && available[3] == 9);
    const unsigned expectedSelections[] = {28, 84, 84, 84};
    for (unsigned platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        unsigned ranks[NW_CATALOG_COMBINATIONS];
        unsigned count = NWCatalogProfileRanks(platform, ranks);
        assert(count == expectedSelections[platform]);
        for (unsigned i = 0; i < count; ++i) {
            unsigned models[NW_CATALOG_SELECTION];
            assert(NWCatalogCombination(ranks[i], models));
            assert(NWCatalogProfileSelection(platform, models, NW_CATALOG_SELECTION));
            if (i) assert(ranks[i] > ranks[i - 1]);
            if (platform == 1) for (unsigned j = 0; j < NW_CATALOG_SELECTION; ++j) assert(models[j] < 3 || models[j] >= 6);
        }
    }
    unsigned rejected[NW_CATALOG_COMBINATIONS];
    assert(!NWCatalogProfileRanks(NW_CATALOG_PLATFORMS, rejected) && !NWCatalogProfileRanks(0, NULL));
    uint8_t data[35]; assert(!NWBTLabCatalogData(data, NW_CATALOG_PLATFORMS, 0) && !NWBTLabCatalogData(data, 0, NW_CATALOG_MODELS));
    uint8_t address[7];
    assert(!NWBTLabCatalogAddress(address, 0, 5, 0) && !NWBTLabCatalogAddress(address, 3, 0, NW_CATALOG_SELECTION));
    assert(NWBTLabCatalogAddress(address, 3, 8, 5) == 7 && address[0] == NWBT_LAB_MULTI_HANDLE + 5);
    unsigned parsed[NW_CATALOG_SELECTION];
    assert(NWCatalogProfileParse("4,0,3", 0, parsed) == 3 && parsed[0] == 4 && parsed[1] == 0 && parsed[2] == 3);
    assert(NWCatalogProfileParse("1,0", 1, parsed) == 2);
    assert(NWCatalogProfileParse("5", 2, parsed) == 1);
    assert(NWCatalogProfileParse("5,2,0", 3, parsed) == 3);
    assert(NWCatalogProfileParse("0,1,2,6,7,8", 1, parsed) == 6);
    assert(NWCatalogProfileParse("0,1,2,9,10,11", 1, parsed) == 6 && parsed[3] == 9 && parsed[4] == 10 && parsed[5] == 11);
    assert(NWCatalogProfileParse("11", 1, parsed) == 1 && parsed[0] == 11);
    const char *invalidGoogle[] = {"12", "99999999999999999999", "01", "010", "10,10", "9,10,11,0,1,2,6", "10,", "10 11", "+10", "1a", "1:0"};
    for (size_t i = 0; i < sizeof invalidGoogle / sizeof *invalidGoogle; ++i) assert(!NWCatalogProfileParse(invalidGoogle[i], 1, parsed));
    const char *invalid[] = {"", "0,0", "0,1,2,3,4,5,6", "9", "0,", ",0", "00", "-1", " 0", "0 1", "0;1"};
    for (size_t i = 0; i < sizeof invalid / sizeof *invalid; ++i) assert(!NWCatalogProfileParse(invalid[i], 2, parsed));
    assert(!NWCatalogProfileParse("5", 0, parsed));
    assert(!NWCatalogProfileParse("3", 1, parsed));
    assert(!NWCatalogProfileParse("0", NW_CATALOG_PLATFORMS, parsed));
    assert(!NWCatalogProfileParse(NULL, 0, parsed));
    assert(!NWCatalogProfileParse("0", 0, NULL));
    for (unsigned platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
            unsigned combination[NW_CATALOG_SELECTION], supported[NW_CATALOG_SELECTION]; size_t count = 0;
            assert(NWCatalogCombination(rank, combination));
            for (unsigned i = 0; i < NW_CATALOG_SELECTION; ++i)
                if (NWCatalogProfileAvailable(platform, combination[i])) supported[count++] = combination[i];
            assert(NWCatalogProfileSelection(platform, supported, count) == (count > 0));
        }
    }
    puts("PASS: 35 model profiles, Samsung capture, stable addresses, AD budgets, 280 available six-model selections and strict decimal input rejection");
}
