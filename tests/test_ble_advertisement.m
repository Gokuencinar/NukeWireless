#import "../src/NWBLEAdvertisement.h"
#include <assert.h>
#include <math.h>
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
    assert([next[@"advertisements"] unsignedIntegerValue] == 2);
    assert([next[@"samples"] count] == 2 && [first[@"samples"] count] == 1);
    assert([invalid[@"samples"] count] == 2);
    assert(NWBLEMatchesFilter(next,@"apple",0) && NWBLEMatchesFilter(next,@"180a",0));
    assert(NWBLEMatchesFilter(next,@"test-UUID",0));
    assert(!NWBLEMatchesFilter(next,@"missing",0));
    assert(NWBLEMatchesFilter(next,@"",1) && NWBLEMatchesFilter(next,@"",2));
    assert(!NWBLEMatchesFilter(@{},@"",1) && !NWBLEMatchesFilter(invalid,@"",2));
    NSArray *samples = @[];
    for (unsigned i=0;i<200;i++) samples = NWBLESignalSamples(samples,-60,i);
    assert(samples.count == 60 && [samples.firstObject[@"time"] intValue] == 140);
    samples = NWBLESignalSamples(samples,-70,199.1);
    assert(samples.count == 60 && [samples.lastObject[@"rssi"] intValue] == -70);
    assert([NWBLESignalSamples(samples,127,199.2) count] == 60);
    NSString *uuid = @"A3EF8A7A-69D7-4BB9-BAAC-BE81FE99FE52";
    NSMutableDictionary *advertisement = [next mutableCopy]; advertisement[@"identifier"] = uuid;
    NSDictionary *history = NWBLEHistoryRecord(nil,advertisement,1000);
    assert(history && !history[@"manufacturer"] && [history[@"samples"] count] == 1);
    history = NWBLEHistoryRecord(history,advertisement,1001);
    assert([history[@"advertisements"] intValue] == 2 && [history[@"firstSeen"] intValue] == 1000);
    NSArray *validated = NWBLEValidateHistory(@[history]);
    assert(validated.count == 1 && [validated[0][@"advertisements"] intValue] == 2);
    assert(NWBLEValidateHistory(@[history,history]).count == 1);
    assert(!NWBLEHistoryRecord(nil,@{},1001));
    assert(!NWBLEValidateHistory(@{}).count);
    NSMutableDictionary *broken = [history mutableCopy]; broken[@"samples"] = @"bad";
    assert(!NWBLEValidateHistory(@[broken]).count);
    broken = [history mutableCopy]; broken[@"firstSeen"] = @1002;
    assert(!NWBLEValidateHistory(@[broken]).count);
    // Only bounded, recent, finite location fixes are accepted; old history stays readable.
    NSDictionary *point = @{@"latitude":@40.4,@"longitude":@(-3.7),@"accuracy":@150,@"time":@1000};
    assert(NWBLEValidateObservation(point,1001,YES));
    assert(!NWBLEValidateObservation(point,1011,YES));
    assert(NWBLEValidateObservation(point,2000,NO));
    NSMutableDictionary *badPoint = [point mutableCopy]; badPoint[@"latitude"] = @91;
    assert(!NWBLEValidateObservation(badPoint,1001,YES));
    badPoint = [point mutableCopy]; badPoint[@"accuracy"] = @(-1);
    assert(!NWBLEValidateObservation(badPoint,1001,YES));
    badPoint[@"accuracy"] = @(NAN); assert(!NWBLEValidateObservation(badPoint,1001,YES));
    assert(!NWBLEValidateObservation(@"bad",1001,YES));
    advertisement[@"observation"] = point;
    NSDictionary *located = NWBLEHistoryRecord(nil,advertisement,1001);
    assert([located[@"observations"] count] == 1);
    located = NWBLEHistoryRecord(located,advertisement,1002); assert([located[@"observations"] count] == 1);
    for (unsigned i=1;i<=12;i++) {
        NSMutableDictionary *moving = [point mutableCopy]; moving[@"time"] = @(1000+i*11);
        advertisement[@"observation"] = moving; located = NWBLEHistoryRecord(located,advertisement,1001+i*11);
    }
    assert([located[@"observations"] count] == 8);
    NSArray *cleanLocations = NWBLEValidateHistory(@[located]);
    assert([cleanLocations[0][@"observations"] count] == 8);
    assert([NWBLEServiceLabels(@[@"fe2c",@"0000180F-0000-1000-8000-00805F9B34FB",@"180F",@"FFFF"]) count] == 2);
    assert(!NWBLEServiceLabels(@[@"Flock",@"Apple",@"09C8"]).count);
    puts("PASS: BLE advertisement merging, unavailable RSSI, truncated manufacturer and immutable snapshots");
} return 0; }
