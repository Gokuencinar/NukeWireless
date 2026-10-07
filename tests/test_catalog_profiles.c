#include "../src/bluetooth/NWBTLab.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    const uint32_t apple[] = {0x2002, 0x200f, 0x200e, 0x2014, 0x200a};
    const uint32_t google[] = {0x92bbbd, 0x8b66ab, 0x9adb11};
    const uint32_t samsung[] = {0xb8b905, 0xd30704, 0x850116, 0x3f6718, 0xeaaa17, 0xab0c46};
    unsigned available[NW_CATALOG_PLATFORMS] = {0};
    uint8_t addresses[24][6]; unsigned addressCount = 0;
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
    assert(available[0] == 5 && available[1] == 3 && available[2] == 6 && available[3] == 6);
    uint8_t data[35]; assert(!NWBTLabCatalogData(data, NW_CATALOG_PLATFORMS, 0) && !NWBTLabCatalogData(data, 0, 6));
    uint8_t address[7];
    assert(!NWBTLabCatalogAddress(address, 0, 5, 0) && !NWBTLabCatalogAddress(address, 3, 0, 3));
    unsigned parsed[3];
    assert(NWCatalogProfileParse("4,0,3", 0, parsed) == 3 && parsed[0] == 4 && parsed[1] == 0 && parsed[2] == 3);
    assert(NWCatalogProfileParse("1,0", 1, parsed) == 2);
    assert(NWCatalogProfileParse("5", 2, parsed) == 1);
    assert(NWCatalogProfileParse("5,2,0", 3, parsed) == 3);
    const char *invalid[] = {"", "0,0", "0,1,2,3", "6", "0,", ",0", "00", "-1", " 0", "0 1", "0;1"};
    for (size_t i = 0; i < sizeof invalid / sizeof *invalid; ++i) assert(!NWCatalogProfileParse(invalid[i], 2, parsed));
    assert(!NWCatalogProfileParse("5", 0, parsed));
    assert(!NWCatalogProfileParse("3", 1, parsed));
    assert(!NWCatalogProfileParse("0", NW_CATALOG_PLATFORMS, parsed));
    assert(!NWCatalogProfileParse(NULL, 0, parsed));
    assert(!NWCatalogProfileParse("0", 0, NULL));
    for (unsigned platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
            unsigned combination[3], supported[3]; size_t count = 0;
            assert(NWCatalogCombination(rank, combination));
            for (unsigned i = 0; i < 3; ++i)
                if (NWCatalogProfileAvailable(platform, combination[i])) supported[count++] = combination[i];
            assert(NWCatalogProfileSelection(platform, supported, count) == (count > 0));
        }
    }
    puts("PASS: four-brand model IDs, Samsung capture, stable distinct addresses, AD budgets, 80 selections and strict input rejection");
}
