#import "NWLANNames.h"
#import "NWDeviceNames.h"
#import "NWNetBIOSName.h"
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static NSURL *descriptionURL(NSData *data, NSString *ip) {
    if (!data.length || data.length > 4096) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray *lines = [text componentsSeparatedByString:@"\r\n"];
    if (lines.count < 3 || ![lines[0] isEqual:@"HTTP/1.1 200 OK"]) return nil;
    NSString *location = nil; BOOL ended = NO;
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i]; if (!line.length) { ended = YES; break; }
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) return nil;
        if ([[line substringToIndex:colon.location].lowercaseString isEqual:@"location"]) {
            if (location) return nil;
            location = [[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    if (!ended || !location.length || location.length > 1024) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:location];
    struct in_addr host;
    // Never follow an advertisement to the WAN, another peer, or a hostname.
    if (![url.scheme.lowercaseString isEqual:@"http"] || ![url.host isEqual:ip] ||
        inet_pton(AF_INET, url.host.UTF8String, &host) != 1 || url.user || url.password || url.fragment ||
        (url.port && (url.port.integerValue < 1 || url.port.integerValue > 65535))) return nil;
    return url.URL;
}
@interface NWUPnPXML : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableArray<NSString *> *path;
@property(nonatomic,strong) NSMutableString *value;
@property(nonatomic,copy) NSString *name;
@end
@implementation NWUPnPXML
- (void)parser:(NSXMLParser *)parser foundInternalEntityDeclarationWithName:(NSString *)name value:(NSString *)value {
    (void)name; (void)value; [parser abortParsing];
}
- (void)parser:(NSXMLParser *)parser foundExternalEntityDeclarationWithName:(NSString *)name publicID:(NSString *)publicID systemID:(NSString *)systemID {
    (void)name; (void)publicID; (void)systemID; [parser abortParsing];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attributes {
    (void)uri; (void)qualified; (void)attributes;
    [self.path addObject:element];
    if (self.path.count > 32 || (self.value && self.path.count > 3)) { [parser abortParsing]; return; }
    if ([self.path isEqual:@[@"root",@"device",@"friendlyName"]]) {
        if (self.name) { [parser abortParsing]; return; }
        self.value = [NSMutableString new];
    }
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)text {
    if (self.value) {
        if (self.value.length + text.length > 255 || self.path.count != 3) { [parser abortParsing]; return; }
        [self.value appendString:text];
    }
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
    (void)parser; (void)uri; (void)qualified;
    if ([element isEqual:@"friendlyName"] && self.value) { self.name = NWCleanDeviceName(self.value); self.value = nil; }
    [self.path removeLastObject];
}
@end
static NSString *upnpName(NSData *data) {
    if (!data.length || data.length > 65536) return nil;
    // Reject DTD/entity declarations in the XML Unicode encodings, before parsing.
    for (NSNumber *encoding in @[@(NSUTF8StringEncoding),@(NSUTF16LittleEndianStringEncoding),@(NSUTF16BigEndianStringEncoding),@(NSUTF32LittleEndianStringEncoding),@(NSUTF32BigEndianStringEncoding)]) {
        for (NSString *declaration in @[@"<!DOCTYPE",@"<!ENTITY"])
            if ([data rangeOfData:[declaration dataUsingEncoding:encoding.unsignedIntegerValue] options:0 range:NSMakeRange(0,data.length)].location != NSNotFound) return nil;
    }
    NWUPnPXML *delegate = [NWUPnPXML new]; delegate.path = [NSMutableArray new];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = delegate; parser.shouldProcessNamespaces = YES; parser.shouldResolveExternalEntities = NO;
    return [parser parse] ? delegate.name : nil;
}
#ifdef NW_NAME_TESTING
NSURL *NWTestSSDPURL(NSData *data, NSString *ip) { return descriptionURL(data,ip); }
NSString *NWTestUPnPName(NSData *data) { return upnpName(data); }
#endif
@interface NWLANQuery : NSObject
@property(nonatomic,copy) NSString *ip, *mac;
@property(nonatomic) BOOL ssdp;
@property(nonatomic) uint16_t transaction;
@property(nonatomic,strong) dispatch_source_t source;
@property(nonatomic) int descriptor;
@end
@implementation NWLANQuery
@end
@interface NWLANNames () <NSURLSessionDataDelegate>
@property(nonatomic,copy) void (^update)(NSString *,NSString *,NSString *,NSUInteger);
@property(nonatomic) BOOL active;
@property(nonatomic) NSUInteger epoch, scheduled, sentNB, sentSSDP, foundNB, foundSSDP, failures, fetches;
@property(nonatomic) uint32_t local, mask;
@property(nonatomic) unsigned interface;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSString *> *peers;
@property(nonatomic,strong) NSMutableArray<NWLANQuery *> *pending;
@property(nonatomic,strong) NSMutableSet<NWLANQuery *> *queries;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSMutableDictionary *> *downloads;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *documents;
@property(nonatomic,strong) NSMutableSet<NSString *> *seen;
@property(nonatomic,strong) NSURLSession *http;
@end
@implementation NWLANNames
- (instancetype)initWithUpdate:(void (^)(NSString *,NSString *,NSString *,NSUInteger))update {
    if ((self = [super init])) { _update = [update copy]; _peers = [NSMutableDictionary new];
        _pending = [NSMutableArray new]; _queries = [NSMutableSet new]; _downloads = [NSMutableDictionary new];
        _documents = [NSMutableArray new]; _seen = [NSMutableSet new]; }
    return self;
}
- (BOOL)networkCurrent {
    struct ifaddrs *interfaces = NULL; BOOL match = NO;
    if (getifaddrs(&interfaces) != 0) return NO;
    for (struct ifaddrs *i = interfaces; i; i = i->ifa_next) {
        if (!i->ifa_addr || !i->ifa_netmask || i->ifa_addr->sa_family != AF_INET || strcmp(i->ifa_name,"en0")) continue;
        uint32_t local = ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr;
        uint32_t mask = ((struct sockaddr_in *)i->ifa_netmask)->sin_addr.s_addr;
        if (!self.local && local && mask) { self.local = local; self.mask = mask; }
        match = local == self.local && mask == self.mask && self.interface == if_nametoindex("en0"); break;
    }
    freeifaddrs(interfaces); return match;
}
- (void)start {
    [self stop]; self.local = self.mask = 0; self.interface = if_nametoindex("en0");
    [self.peers removeAllObjects]; [self.seen removeAllObjects];
    self.scheduled = self.sentNB = self.sentSSDP = self.foundNB = self.foundSSDP = self.failures = self.fetches = 0;
    self.active = self.interface && [self networkCurrent];
}
- (void)stop {
    self.active = NO; self.epoch++;
    for (NWLANQuery *query in self.queries) dispatch_source_cancel(query.source);
    [self.queries removeAllObjects]; [self.pending removeAllObjects]; [self.documents removeAllObjects];
    [self.http invalidateAndCancel]; self.http = nil; [self.downloads removeAllObjects];
}
- (BOOL)currentIP:(NSString *)ip mac:(NSString *)mac {
    return self.active && ip.length && mac.length && [self.peers[ip] isEqual:mac] && [self networkCurrent];
}
- (void)trackIP:(NSString *)ip mac:(NSString *)mac {
    struct in_addr address;
    if (!self.active || !mac.length || inet_pton(AF_INET,ip.UTF8String,&address) != 1 ||
        address.s_addr == self.local || (address.s_addr & self.mask) != (self.local & self.mask) ||
        address.s_addr == (self.local & self.mask) || address.s_addr == ((self.local & self.mask) | ~self.mask) ||
        [self.peers[ip] isEqual:mac] || (!self.peers[ip] && self.peers.count >= 128) || self.scheduled >= 256) return;
    self.peers[ip] = mac;
    // One query of each kind per discovered peer, never an expanded subnet sweep.
    for (NSNumber *ssdp in @[@NO,@YES]) {
        self.scheduled++;
        NWLANQuery *query = [NWLANQuery new]; query.ip = ip; query.mac = mac; query.ssdp = ssdp.boolValue;
        query.transaction = (uint16_t)arc4random_uniform(65536); [self.pending addObject:query];
    }
    [self pump];
}
- (void)complete:(NWLANQuery *)query {
    if (![self.queries containsObject:query]) return;
    dispatch_source_cancel(query.source); [self.queries removeObject:query]; [self pump];
}
- (void)pump {
    while (self.active && self.pending.count && self.queries.count < 8) {
        NWLANQuery *query = self.pending.firstObject; [self.pending removeObjectAtIndex:0];
        if (![self currentIP:query.ip mac:query.mac]) continue;
        int fd = socket(AF_INET,SOCK_DGRAM,0); if (fd < 0) { self.failures++; continue; }
        struct sockaddr_in local = {0}, peer = {0}; local.sin_family = peer.sin_family = AF_INET;
        local.sin_len = peer.sin_len = sizeof(struct sockaddr_in);
        local.sin_addr.s_addr = self.local; inet_pton(AF_INET,query.ip.UTF8String,&peer.sin_addr);
        peer.sin_port = htons(query.ssdp ? 1900 : 137);
        if (fcntl(fd,F_SETFL,O_NONBLOCK) || fcntl(fd,F_SETFD,FD_CLOEXEC) ||
            setsockopt(fd,IPPROTO_IP,IP_BOUND_IF,&_interface,sizeof(_interface)) ||
            bind(fd,(struct sockaddr *)&local,sizeof(local))) { close(fd); self.failures++; continue; }
        NSData *request;
        if (query.ssdp) {
            NSString *text = [NSString stringWithFormat:@"M-SEARCH * HTTP/1.1\r\nHOST: %@:1900\r\nMAN: \"ssdp:discover\"\r\nST: upnp:rootdevice\r\n\r\n",query.ip];
            request = [text dataUsingEncoding:NSUTF8StringEncoding];
        } else { uint8_t packet[50]; NWNBStatusRequest(packet,query.transaction); request = [NSData dataWithBytes:packet length:50]; }
        if (sendto(fd,request.bytes,request.length,0,(struct sockaddr *)&peer,sizeof(peer)) != (ssize_t)request.length) {
            close(fd); self.failures++; continue;
        }
        if (query.ssdp) self.sentSSDP++; else self.sentNB++;
        query.descriptor = fd;
        query.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,dispatch_get_main_queue());
        if (!query.source) { close(fd); self.failures++; continue; }
        dispatch_source_set_cancel_handler(query.source, ^{ close(fd); });
        __weak NWLANNames *weak = self; __weak NWLANQuery *weakQuery = query; NSUInteger epoch = self.epoch;
        dispatch_source_set_event_handler(query.source, ^{
            NWLANNames *owner = weak; NWLANQuery *q = weakQuery;
            if (!owner || !q || owner.epoch != epoch) return;
            // Bound each callback even for a peer flooding responses.
            for (unsigned i = 0; i < 8; i++) {
                uint8_t bytes[4097]; struct sockaddr_in sender = {0}; socklen_t length = sizeof(sender);
                ssize_t count = recvfrom(fd,bytes,sizeof(bytes),0,(struct sockaddr *)&sender,&length);
                if (count < 0) { if (errno != EAGAIN && errno != EWOULDBLOCK) { owner.failures++; [owner complete:q]; } break; }
                if (count == 0 || count > 4096 || sender.sin_family != AF_INET || sender.sin_addr.s_addr != peer.sin_addr.s_addr ||
                    (!q.ssdp && sender.sin_port != htons(137)) || ![owner currentIP:q.ip mac:q.mac]) continue;
                if (q.ssdp) {
                    NSURL *url = descriptionURL([NSData dataWithBytes:bytes length:(NSUInteger)count],q.ip);
                    if (url) { [owner document:url query:q]; [owner complete:q]; break; }
                } else {
                    char name[16];
                    if (NWNBStatusName(bytes,(size_t)count,q.transaction,name)) {
                        NSString *clean = NWCleanDeviceName(@(name));
                        if (clean) { owner.foundNB++; owner.update(q.ip,q.mac,clean,30); }
                        [owner complete:q]; break;
                    }
                }
            }
        });
        [self.queries addObject:query]; dispatch_resume(query.source);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            NWLANNames *owner = weak; NWLANQuery *q = weakQuery;
            if (owner && q && owner.epoch == epoch) [owner complete:q];
        });
    }
}
- (void)document:(NSURL *)url query:(NWLANQuery *)query {
    if (self.fetches >= 32 || [self.seen containsObject:query.ip]) return;
    [self.seen addObject:query.ip]; self.fetches++;
    [self.documents addObject:@{@"url":url,@"ip":query.ip,@"mac":query.mac}]; [self pumpDocuments];
}
- (void)pumpDocuments {
    if (!self.active || !self.documents.count) return;
    if (!self.http) {
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 3; config.timeoutIntervalForResource = 4;
        config.HTTPShouldSetCookies = NO; config.HTTPShouldUsePipelining = NO;
        config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil; config.URLCache = nil;
        config.connectionProxyDictionary = @{};
        self.http = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }
    while (self.documents.count && self.downloads.count < 4) {
        NSDictionary *document = self.documents.firstObject; [self.documents removeObjectAtIndex:0];
        if (![self currentIP:document[@"ip"] mac:document[@"mac"]]) continue;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:document[@"url"]];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        NSURLSessionDataTask *task = [self.http dataTaskWithRequest:request];
        NSMutableDictionary *entry = [document mutableCopy]; entry[@"bytes"] = [NSMutableData new]; entry[@"accepted"] = @NO;
        self.downloads[@(task.taskIdentifier)] = entry; [task resume];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    (void)session; (void)task; (void)response; (void)request; completion(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completion {
    (void)session; (void)task; (void)challenge; completion(NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    NSMutableDictionary *entry = self.downloads[@(task.taskIdentifier)];
    BOOL accepted = session == self.http && [response isKindOfClass:NSHTTPURLResponse.class] &&
        ((NSHTTPURLResponse *)response).statusCode == 200 && response.expectedContentLength <= 65536 &&
        [response.URL isEqual:entry[@"url"]] && [self currentIP:entry[@"ip"] mac:entry[@"mac"]];
    entry[@"accepted"] = @(accepted); completion(accepted ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (session != self.http) return;
    NSMutableDictionary *entry = self.downloads[@(task.taskIdentifier)]; NSMutableData *bytes = entry[@"bytes"];
    if (![entry[@"accepted"] boolValue] || bytes.length + data.length > 65536 || ![self currentIP:entry[@"ip"] mac:entry[@"mac"]]) {
        entry[@"accepted"] = @NO; [task cancel]; return;
    }
    [bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (session != self.http) return;
    NSDictionary *entry = self.downloads[@(task.taskIdentifier)];
    if (!error && [entry[@"accepted"] boolValue] && [self currentIP:entry[@"ip"] mac:entry[@"mac"]]) {
        NSString *name = upnpName(entry[@"bytes"]);
        if (name) { self.foundSSDP++; self.update(entry[@"ip"],entry[@"mac"],name,50); }
    } else self.failures++;
    [self.downloads removeObjectForKey:@(task.taskIdentifier)]; [self pumpDocuments];
}
- (NSDictionary *)diagnostics {
    return @{@"netbios_queries":@(self.sentNB),@"netbios_names":@(self.foundNB),
        @"ssdp_queries":@(self.sentSSDP),@"upnp_documents":@(self.fetches),@"upnp_names":@(self.foundSSDP),
        @"lan_lookup_errors":@(self.failures)};
}
@end
