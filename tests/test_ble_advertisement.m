#import "../src/NWBLEAdvertisement.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    uint8_t apple[] = {0x4C, 0x00, 0x07};
    uint8_t unknown[] = {0x00, 0x00};
    assert(NWBLEManufacturer([NSData dataWithBytes:apple length:1]) == nil);
    assert([NWBLEManufacturer([NSData dataWithBytes:unknown length:2]) isEqual:@"0x0000"]);
    NSData *data = [NSData dataWithBytes:apple length:3];
    NSDictionary *first = NWBLEUpdateRecord(nil, @"test-uuid", @"Headphones", -60, data, @[@"180F"], @YES, 1);
    assert([first[@"company"] isEqual:@"Apple (0x004C)"]);
    NSDictionary *next = NWBLEUpdateRecord(first, @"test-uuid", nil, -70, nil, @[@"180F", @"180A"], nil, 2);
    assert([next[@"name"] isEqual:@"Headphones"] && [next[@"manufacturer"] isEqual:data]);
    assert([next[@"services"] count] == 2 && [first[@"services"] count] == 1);
    assert([next[@"rssi"] integerValue] == -70 && [first[@"rssi"] integerValue] == -60);
    NSDictionary *invalid = NWBLEUpdateRecord(next, @"test-uuid", nil, 127, [NSData data], nil, @NO, 3);
    assert(invalid[@"rssi"] == nil && invalid[@"company"] == nil);
    assert(![invalid[@"connectable"] boolValue]);
    assert([next[@"connectable"] boolValue]);
    puts("PASS: BLE advertisement merging, unavailable RSSI, truncated manufacturer and immutable snapshots");
} return 0; }
