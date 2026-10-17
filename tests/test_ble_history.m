#import "../src/NWBLEHistory.h"
#import "../src/NWBLEAdvertisement.h"
#include <assert.h>
static void waitUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    while (!condition() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(condition());
}
int main(void) { @autoreleasepool {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *url = [directory URLByAppendingPathComponent:@"history.json"];
    NWBLEHistory *store = [[NWBLEHistory alloc] initWithURL:url];
    waitUntil(^BOOL { return !store.loading; });
    NSString *uuid = @"A3EF8A7A-69D7-4BB9-BAAC-BE81FE99FE52";
    NSDictionary *record = NWBLEUpdateRecord(nil,uuid,@"Test TV",-60,[NSData dataWithBytes:"\x4c\x00\x07" length:3],@[@"180F"],@YES,5);
    NSMutableDictionary *located = [record mutableCopy]; located[@"observation"] = @{@"latitude":@40,@"longitude":@(-3),@"accuracy":@150,@"time":@1000};
    [store observe:located atTime:1000]; [store observe:record atTime:1001]; [store flush];
    __block BOOL exported = NO;
    [store exportWithCompletion:^(NSURL *file,NSError *error) {
        assert(file && !error); NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:file] options:0 error:NULL];
        assert([root[@"devices"] count] == 1 && [root[@"devices"][0][@"advertisements"] intValue] == 2);
        assert(!root[@"devices"][0][@"manufacturer"]);
        assert([root[@"devices"][0][@"observations"] count] == 1); exported = YES;
    }];
    waitUntil(^BOOL { return exported; });
    NWBLEHistory *reloaded = [[NWBLEHistory alloc] initWithURL:url];
    waitUntil(^BOOL { return !reloaded.loading; });
    assert(reloaded.records.count == 1 && [reloaded.records[0][@"name"] isEqual:@"Test TV"]);
    assert([reloaded.records[0][@"observations"] count] == 1);
    [reloaded clearLocations]; assert(!reloaded.records[0][@"observations"] && [reloaded.records[0][@"advertisements"] intValue] == 2);
    [reloaded clear]; __block BOOL cleared = NO;
    [reloaded exportWithCompletion:^(NSURL *file,NSError *error) { assert(file && !error); cleared = YES; }];
    waitUntil(^BOOL { return cleared; });
    NWBLEHistory *empty = [[NWBLEHistory alloc] initWithURL:url];
    // Clearing immediately must not be undone by asynchronous loading.
    [empty clear]; waitUntil(^BOOL { return !empty.loading; }); assert(!empty.records.count);
    for (unsigned i=0;i<210;i++) {
        NSString *identifier = [NSString stringWithFormat:@"00000000-0000-4000-8000-%012u",i];
        [empty observe:@{@"identifier":identifier,@"services":@[]} atTime:2000+i];
    }
    assert(empty.records.count == 200 && [empty.records.firstObject[@"seen"] intValue] == 2209);
    // Invalid on-disk input is reported and left intact until explicit clear.
    NSURL *bad = [directory URLByAppendingPathComponent:@"bad.json"];
    NSData *corrupt = [@"{invalid" dataUsingEncoding:NSUTF8StringEncoding]; assert([corrupt writeToURL:bad atomically:YES]);
    NWBLEHistory *broken = [[NWBLEHistory alloc] initWithURL:bad]; waitUntil(^BOOL { return !broken.loading; });
    assert(broken.storageError && [[NSData dataWithContentsOfURL:bad] isEqual:corrupt]);
    // Drain background writes before removing this test-owned temporary directory.
    __block BOOL drained = NO; [empty flush]; [empty exportWithCompletion:^(NSURL *file,NSError *error) { assert(file && !error); drained = YES; }];
    waitUntil(^BOOL { return drained; });
    puts("PASS: BLE history persistence, export, load/clear race, bounds and malformed-file preservation");
} return 0; }
