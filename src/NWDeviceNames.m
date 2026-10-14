#import "NWDeviceNames.h"
#import "NWLANNames.h"
#import <arpa/inet.h>
#import <net/if.h>
#import <dns_sd.h>

NSArray<NSString *> *NWNameServiceTypes(void) {
    return @[@"_airplay._tcp", @"_raop._tcp", @"_companion-link._tcp", @"_apple-mobdev2._tcp",
             @"_googlecast._tcp", @"_androidtvremote2._tcp", @"_smb._tcp", @"_rdp._tcp",
             @"_ssh._tcp", @"_workstation._tcp", @"_device-info._tcp", @"_ipp._tcp",
             @"_printer._tcp", @"_http._tcp", @"_hap._tcp"];
}
BOOL NWDeviceNameIsPlaceholder(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return YES;
    NSString *name = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (!name.length || [@[@"unknown", @"unknown host", @"device", @"equipo"] containsObject:name]) return YES;
    // Only an entire generated label is a placeholder: "Device Room" is a real name.
    return [name rangeOfString:@"^(device|equipo) \\.?[0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}
NSString *NWCleanDeviceName(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length > 255 ||
        [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    NSString *name = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([name hasSuffix:@"."]) name = [name substringToIndex:name.length - 1];
    if ([name.lowercaseString hasSuffix:@".local"]) name = [name substringToIndex:name.length - 6];
    struct in_addr ipv4; struct in6_addr ipv6;
    if (!name.length || name.length > 80 || NWDeviceNameIsPlaceholder(name) ||
        inet_pton(AF_INET, name.UTF8String, &ipv4) == 1 || inet_pton(AF_INET6, name.UTF8String, &ipv6) == 1 ||
        [[NSUUID alloc] initWithUUIDString:name]) return nil;
    return name;
}
NSString *NWBonjourFriendlyName(NSString *type, NSData *txt) {
    // Google Cast's advertised fn is the friendly name, not md (model) or id.
    if (![type isEqual:@"_googlecast._tcp."] || !txt.length || txt.length > 4096) return nil;
    NSData *name = [NSNetService dictionaryFromTXTRecordData:txt][@"fn"];
    if (!name.length || name.length > 255) return nil;
    return NWCleanDeviceName([[NSString alloc] initWithData:name encoding:NSUTF8StringEncoding]);
}

@class NWDeviceNames;
@interface NWNameQuery : NSObject
@property(nonatomic) DNSServiceRef reference;
@property(nonatomic, copy) NSString *ip, *mac;
@property(nonatomic, weak) NWDeviceNames *owner;
@end
@implementation NWNameQuery
@end

@interface NWDeviceNames () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic, copy) void (^update)(NSString *, NSString *, NSString *);
@property(nonatomic) BOOL active, networking;
@property(nonatomic) NSUInteger session, serviceCount, queryCount, failures, updates;
@property(nonatomic) NSInteger dnsError, bonjourError;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *peers;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *names;
@property(nonatomic, strong) NSMutableArray<NSNetServiceBrowser *> *browsers;
@property(nonatomic, strong) NSMutableSet<NSNetService *> *services;
@property(nonatomic, strong) NSMutableSet<NSString *> *seenServices;
@property(nonatomic, strong) NSMutableArray<NSNetService *> *waitingServices;
@property(nonatomic, strong) NSMutableArray<NWNameQuery *> *pending, *queries;
@property(nonatomic, strong) NWLANNames *lan;
- (void)offer:(NSString *)name ip:(NSString *)ip mac:(NSString *)mac rank:(NSUInteger)rank;
- (void)complete:(NWNameQuery *)query;
- (void)pump;
@end

// PTR RDATA from DNS-SD is a length-prefixed, uncompressed domain name.
// Reject malformed labels, compression pointers and trailing garbage.
static NSString *ptrName(const void *bytes, uint16_t size) {
    if (!bytes || size < 2 || size > 255) return nil;
    const uint8_t *data = bytes; NSUInteger offset = 0;
    NSMutableArray *labels = [NSMutableArray new];
    while (offset < size) {
        NSUInteger length = data[offset++];
        if (!length) return offset == size && labels.count ? [labels componentsJoinedByString:@"."] : nil;
        if (length > 63 || length > size - offset) return nil;
        NSString *label = [[NSString alloc] initWithBytes:data + offset length:length encoding:NSUTF8StringEncoding];
        if (!label || [label containsString:@"."]) return nil;
        [labels addObject:label]; offset += length;
    }
    return nil;
}
#ifdef NW_NAME_TESTING
NSString *NWTestPTRName(NSData *data) { return data.length <= 255 ? ptrName(data.bytes, (uint16_t)data.length) : nil; }
#endif
static void reverseReply(DNSServiceRef ref, DNSServiceFlags flags, uint32_t interface,
                         DNSServiceErrorType error, const char *fullname, uint16_t type,
                         uint16_t rrclass, uint16_t length, const void *data, uint32_t ttl, void *context) {
    (void)ref; (void)interface; (void)fullname; (void)rrclass; (void)ttl;
    NWNameQuery *query = (__bridge NWNameQuery *)context;
    NWDeviceNames *owner = query.owner;
    if (!error && type == kDNSServiceType_PTR && (flags & kDNSServiceFlagsAdd))
        [owner offer:ptrName(data, length) ip:query.ip mac:query.mac rank:20];
    if (error) { owner.failures++; owner.dnsError = error; }
    // Deallocation occurs on the same main queue, after the reply has returned.
    dispatch_async(dispatch_get_main_queue(), ^{ [owner complete:query]; });
}

@implementation NWDeviceNames
- (instancetype)initWithUpdate:(void (^)(NSString *, NSString *, NSString *))update {
    if ((self = [super init])) {
        _update = [update copy]; _peers = [NSMutableDictionary new]; _names = [NSMutableDictionary new];
        _browsers = [NSMutableArray new]; _services = [NSMutableSet new];
        _seenServices = [NSMutableSet new]; _waitingServices = [NSMutableArray new];
        _pending = [NSMutableArray new]; _queries = [NSMutableArray new];
    }
    return self;
}
- (void)dealloc { [self stop]; }
- (void)start {
    NSAssert(NSThread.isMainThread, @"Name discovery belongs to main");
    [self stop]; self.active = YES; self.networking = YES;
    [self.peers removeAllObjects]; [self.names removeAllObjects]; [self.seenServices removeAllObjects];
    self.serviceCount = self.queryCount = self.failures = self.updates = 0;
    self.dnsError = self.bonjourError = 0;
    __weak NWDeviceNames *resolver = self;
    self.lan = [[NWLANNames alloc] initWithUpdate:^(NSString *ip, NSString *mac, NSString *name, NSUInteger rank) {
        [resolver offer:name ip:ip mac:mac rank:rank];
    }];
    [self.lan start];
    NSUInteger session = self.session;
    for (NSString *type in NWNameServiceTypes()) {
        NSNetServiceBrowser *browser = [NSNetServiceBrowser new]; browser.delegate = self;
        [self.browsers addObject:browser]; [browser searchForServicesOfType:[type stringByAppendingString:@"."] inDomain:@"local."];
    }
    __weak NWDeviceNames *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NWDeviceNames *owner = weak;
        if (owner && owner.session == session) [owner stopBonjour];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NWDeviceNames *owner = weak;
        if (owner && owner.session == session) [owner stop];
    });
}
- (void)stopBonjour {
    for (NSNetServiceBrowser *browser in self.browsers) { browser.delegate = nil; [browser stop]; }
    for (NSNetService *service in self.services) { service.delegate = nil; [service stop]; }
    [self.browsers removeAllObjects]; [self.services removeAllObjects];
    [self.waitingServices removeAllObjects];
}
- (void)stop {
    self.active = NO; self.session++;
    [self.lan stop];
    [self stopBonjour]; [self.pending removeAllObjects];
    for (NWNameQuery *query in self.queries) {
        if (query.reference) { DNSServiceRefDeallocate(query.reference); query.reference = NULL; }
    }
    [self.queries removeAllObjects];
}
- (void)trackIP:(NSString *)ip mac:(NSString *)mac {
    struct in_addr address;
    if (!self.active || inet_pton(AF_INET, ip.UTF8String, &address) != 1 || !mac.length) return;
    if ([self.peers[ip] isEqual:mac]) return;
    if (self.peers.count >= 128 && !self.peers[ip]) return;
    if (self.peers[ip]) [self.names removeObjectForKey:ip];
    self.peers[ip] = mac;
    if (self.networking) [self.lan trackIP:ip mac:mac];
    NSDictionary *evidence = self.names[ip];
    if (evidence) self.update(ip, mac, evidence[@"name"]);
    if (!self.networking || self.queryCount >= 128) return;
    self.queryCount++;
    NWNameQuery *query = [NWNameQuery new]; query.owner = self; query.ip = ip; query.mac = mac;
    [self.pending addObject:query]; [self pump];
}
- (void)pump {
    while (self.active && self.pending.count && self.queries.count < 8) {
        NWNameQuery *query = self.pending.firstObject; [self.pending removeObjectAtIndex:0];
        if (![self.peers[query.ip] isEqual:query.mac]) continue;
        NSArray *parts = [query.ip componentsSeparatedByString:@"."];
        NSString *reverse = [NSString stringWithFormat:@"%@.%@.%@.%@.in-addr.arpa.", parts[3], parts[2], parts[1], parts[0]];
        unsigned interface = if_nametoindex("en0");
        DNSServiceRef reference = NULL;
        DNSServiceErrorType error = interface ? DNSServiceQueryRecord(&reference, 0, interface,
            reverse.UTF8String, kDNSServiceType_PTR, kDNSServiceClass_IN, reverseReply, (__bridge void *)query) : kDNSServiceErr_BadInterfaceIndex;
        query.reference = reference;
        if (!error) error = DNSServiceSetDispatchQueue(query.reference, dispatch_get_main_queue());
        if (error) {
            if (query.reference) { DNSServiceRefDeallocate(query.reference); query.reference = NULL; }
            self.failures++; self.dnsError = error; continue;
        }
        [self.queries addObject:query];
        __weak NWDeviceNames *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [weak complete:query]; });
    }
}
- (void)complete:(NWNameQuery *)query {
    if (![self.queries containsObject:query]) return;
    if (query.reference) { DNSServiceRefDeallocate(query.reference); query.reference = NULL; }
    [self.queries removeObject:query]; [self pump];
}
- (void)offer:(NSString *)value ip:(NSString *)ip mac:(NSString *)mac rank:(NSUInteger)rank {
    if (!self.active || (mac && ![self.peers[ip] isEqual:mac])) return;
    NSString *name = NWCleanDeviceName(value); if (!name) return;
    if (!self.names[ip] && self.names.count >= 128) return;
    NSDictionary *old = self.names[ip];
    if (old && ([old[@"rank"] unsignedIntegerValue] > rank ||
        ([old[@"rank"] unsignedIntegerValue] == rank && [old[@"name"] compare:name] != NSOrderedDescending))) return;
    self.names[ip] = @{@"name":name, @"rank":@(rank)};
    if (self.peers[ip]) { self.updates++; self.update(ip, self.peers[ip], name); }
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)more {
    (void)more;
    if (!self.active || ![self.browsers containsObject:browser] || self.serviceCount >= 128) return;
    NSString *key = [NSString stringWithFormat:@"%@/%@/%@", service.domain, service.type, service.name];
    if ([self.seenServices containsObject:key]) return;
    [self.seenServices addObject:key]; self.serviceCount++; [self.waitingServices addObject:service];
    [self pumpServices];
}
- (void)pumpServices {
    while (self.active && self.waitingServices.count && self.services.count < 8) {
        NSNetService *service = self.waitingServices.firstObject; [self.waitingServices removeObjectAtIndex:0];
        [self.services addObject:service]; service.delegate = self; [service resolveWithTimeout:3];
    }
}
- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (!self.active || ![self.services containsObject:service]) return;
    NSString *friendly = service.name;
    NSString *txtName = NWBonjourFriendlyName(service.type, service.TXTRecordData);
    // RAOP instances carry a hardware prefix; it is not the user-visible name.
    if ([service.type isEqualToString:@"_raop._tcp."]) {
        NSRange marker = [friendly rangeOfString:@"@"];
        if (marker.location != NSNotFound) friendly = [friendly substringFromIndex:marker.location + 1];
    }
    // Pairing identifiers and device-info instances often contain opaque IDs.
    BOOL friendlyService = ![@[@"_apple-mobdev2._tcp.", @"_device-info._tcp.", @"_companion-link._tcp."] containsObject:service.type];
    for (NSData *data in service.addresses) {
        if (data.length < sizeof(struct sockaddr_in)) continue;
        const struct sockaddr_in *address = data.bytes;
        if (address->sin_family != AF_INET) continue;
        char text[INET_ADDRSTRLEN]; if (!inet_ntop(AF_INET, &address->sin_addr, text, sizeof(text))) continue;
        NSString *ip = @(text);
        [self offer:service.hostName ip:ip mac:nil rank:40];
        if (friendlyService) [self offer:friendly ip:ip mac:nil rank:60];
        if (txtName) [self offer:txtName ip:ip mac:nil rank:70];
    }
    service.delegate = nil; [service stop]; [self.services removeObject:service];
    [self pumpServices];
}
- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)error {
    if (!self.active || ![self.services containsObject:service]) return;
    self.failures++; self.bonjourError = [error[NSNetServicesErrorCode] integerValue];
    service.delegate = nil; [service stop]; [self.services removeObject:service];
    [self pumpServices];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary *)error {
    if (!self.active || ![self.browsers containsObject:browser]) return;
    self.failures++; self.bonjourError = [error[NSNetServicesErrorCode] integerValue];
}
- (NSDictionary *)diagnostics {
    NSMutableDictionary *result = [@{@"peers":@(self.peers.count), @"names":@(self.names.count), @"updates":@(self.updates),
             @"services":@(self.serviceCount), @"reverse_queries":@(self.queryCount), @"lookup_errors":@(self.failures),
             @"last_dns_error":@(self.dnsError), @"last_bonjour_error":@(self.bonjourError), @"active":@(self.active)} mutableCopy];
    [result addEntriesFromDictionary:self.lan.diagnostics ?: @{}];
    return result;
}
#ifdef NW_NAME_TESTING
- (void)testBegin { self.active = YES; }
- (void)testName:(NSString *)name ip:(NSString *)ip mac:(NSString *)mac rank:(NSUInteger)rank {
    [self offer:name ip:ip mac:mac rank:rank];
}
#endif
@end
