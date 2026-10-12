#import "../src/NWDeviceNames.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    assert(NWDeviceNameIsPlaceholder(@"Device .42"));
    assert(NWDeviceNameIsPlaceholder(@"Equipo 42"));
    assert(NWDeviceNameIsPlaceholder(@"Unknown Host"));
    assert(!NWDeviceNameIsPlaceholder(@"Device Room"));
    assert([NWCleanDeviceName(@"  Salón.local. ") isEqual:@"Salón"]);
    assert([NWCleanDeviceName(@"Office-PC.lan.") isEqual:@"Office-PC.lan"]);
    for (NSString *value in @[@"192.168.1.2", @"::1", @"Device", @"a\nb", @"", @"550e8400-e29b-41d4-a716-446655440000"])
        assert(!NWCleanDeviceName(value));
    const unsigned char valid[] = {5,'s','a','l','o','n',5,'l','o','c','a','l',0};
    assert([NWTestPTRName([NSData dataWithBytes:valid length:sizeof(valid)]) isEqual:@"salon.local"]);
    const unsigned char pointer[] = {0xc0,0x0c}, shortLabel[] = {5,'x',0}, trailing[] = {1,'x',0,1};
    assert(!NWTestPTRName([NSData dataWithBytes:pointer length:sizeof(pointer)]));
    assert(!NWTestPTRName([NSData dataWithBytes:shortLabel length:sizeof(shortLabel)]));
    assert(!NWTestPTRName([NSData dataWithBytes:valid length:sizeof(valid)-1]));
    assert(!NWTestPTRName([NSData dataWithBytes:trailing length:sizeof(trailing)]));
    NSMutableArray *updates = [NSMutableArray new];
    NWDeviceNames *resolver = [[NWDeviceNames alloc] initWithUpdate:^(NSString *ip, NSString *mac, NSString *name) {
        [updates addObject:@[ip,mac,name]];
    }];
    [resolver testBegin];
    // Bonjour often resolves before the native ARP scanner finds the device.
    [resolver testName:@"Living Room.local." ip:@"192.0.2.5" mac:nil rank:40];
    assert(updates.count == 0);
    [resolver trackIP:@"192.0.2.5" mac:@"aa:bb:cc:dd:ee:01"];
    assert([updates.lastObject[2] isEqual:@"Living Room"]);
    [resolver testName:@"dns.lan" ip:@"192.0.2.5" mac:@"aa:bb:cc:dd:ee:01" rank:20];
    assert(updates.count == 1); // Weaker DNS cannot displace Bonjour.
    [resolver testName:@"TV Salón" ip:@"192.0.2.5" mac:nil rank:60];
    assert([updates.lastObject[2] isEqual:@"TV Salón"]);
    [resolver trackIP:@"192.0.2.5" mac:@"aa:bb:cc:dd:ee:02"];
    [resolver testName:@"Old peer" ip:@"192.0.2.5" mac:@"aa:bb:cc:dd:ee:01" rank:80];
    assert(updates.count == 2); // Address reuse must reject the old PTR reply.
    [resolver testName:@"New peer" ip:@"192.0.2.5" mac:@"aa:bb:cc:dd:ee:02" rank:20];
    assert(updates.count == 3);
    [resolver stop];
    [resolver testName:@"Late callback" ip:@"192.0.2.5" mac:nil rank:80];
    assert(updates.count == 3);
    puts("Device names: normalization, PTR bounds, priorities, early evidence, address reuse and cancellation passed");
} return 0; }
