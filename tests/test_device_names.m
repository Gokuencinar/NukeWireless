#import "../src/NWDeviceNames.h"
#import "../src/NWLANNames.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
    NSData *txt = [NSNetService dataFromTXTRecordDictionary:@{@"fn":utf8(@"TV Salón"),@"md":utf8(@"Chromecast"),@"id":utf8(@"opaque-id")}];
    assert([NWBonjourFriendlyName(@"_googlecast._tcp.",txt) isEqual:@"TV Salón"]);
    assert(!NWBonjourFriendlyName(@"_http._tcp.",txt));
    assert(!NWBonjourFriendlyName(@"_googlecast._tcp.",[NSNetService dataFromTXTRecordDictionary:@{@"md":utf8(@"Chromecast")} ]));
    assert(!NWBonjourFriendlyName(@"_googlecast._tcp.",[NSMutableData dataWithLength:4097]));
    NSString *(^reply)(NSString *) = ^NSString *(NSString *url) { return [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nLOCATION: %@\r\nST: upnp:rootdevice\r\n\r\n",url]; };
    assert(NWTestSSDPURL(utf8(reply(@"http://192.0.2.5:8000/device.xml")),@"192.0.2.5"));
    for (NSString *url in @[@"http://192.0.2.6/a",@"http://example.org/a",@"file:///a",@"http://user:pass@192.0.2.5/a",@"http://192.0.2.5:0/a",@"http://192.0.2.5:65536/a",@"http://192.0.2.5/a#x"])
        assert(!NWTestSSDPURL(utf8(reply(url)),@"192.0.2.5"));
    assert(!NWTestSSDPURL(utf8(@"HTTP/1.1 200 OK\r\nLOCATION: http://192.0.2.5/a\r\nLOCATION: http://192.0.2.5/b\r\n\r\n"),@"192.0.2.5"));
    assert(!NWTestSSDPURL(utf8(@"HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\n\r\n"),@"192.0.2.5"));
    assert([NWTestUPnPName(utf8(@"<root xmlns='urn:schemas-upnp-org:device-1-0'><device><friendlyName>TV Salón</friendlyName><deviceList><device><friendlyName>Embedded</friendlyName></device></deviceList></device></root>")) isEqual:@"TV Salón"]);
    for (NSString *xml in @[@"<root><device><friendlyName>Device</friendlyName></device></root>",@"<root><device><friendlyName>A<b>B</b></friendlyName></device></root>",@"<root><device><friendlyName>A</friendlyName><friendlyName>B</friendlyName></device></root>",@"<root><device><friendlyName>A</friendlyName></device>",@"<!DOCTYPE root [<!ENTITY x 'TV'>]><root><device><friendlyName>&x;</friendlyName></device></root>"])
        assert(!NWTestUPnPName(utf8(xml)));
    assert(!NWTestUPnPName([NSMutableData dataWithLength:65537]));
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
    NSString *diagnostic = [resolver.diagnostics description];
    assert(![diagnostic containsString:@"192.0.2"] && ![diagnostic containsString:@"New peer"]);
    NWDeviceNames *bounded = [[NWDeviceNames alloc] initWithUpdate:^(NSString *ip, NSString *mac, NSString *name) {
        (void)ip; (void)mac; (void)name;
    }];
    [bounded testBegin];
    for (int i = 1; i <= 200; ++i) {
        NSString *ip = [NSString stringWithFormat:@"192.0.2.%d", i];
        [bounded trackIP:ip mac:@"aa:bb:cc:dd:ee:01"];
        [bounded testName:@"Host" ip:ip mac:nil rank:20];
    }
    assert([bounded.diagnostics[@"peers"] unsignedIntegerValue] == 128);
    assert([bounded.diagnostics[@"names"] unsignedIntegerValue] == 128);
    [bounded stop];
    [resolver stop];
    [resolver testName:@"Late callback" ip:@"192.0.2.5" mac:nil rank:80];
    assert(updates.count == 3);
    puts("Device names: normalization, PTR bounds, priorities, early evidence, address reuse and cancellation passed");
} return 0; }
