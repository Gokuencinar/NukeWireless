#import "NWScanBridge.h"
#import "NWPolicy.h"
#import "NWResources.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <signal.h>
#import <errno.h>
#import <QuartzCore/QuartzCore.h>

// Names below are ABI identifiers in the unchanged, SHA-256-pinned app.
@interface NWLegacyScanner : NSObject
- (instancetype)initWithDelegate:(id)delegate andEnableHotspot:(BOOL)hotspot;
@property (nonatomic, weak) id delegate;
@property (nonatomic) BOOL enableHotspot;
@property (nonatomic, strong) NSOperationQueue *queue;
- (void)start;
- (void)stop;
@end

NSNotificationName const NWStateChanged = @"NukeWirelessStateChanged";
static NWScanState state;
static id wifiAdapter;
static NSMutableDictionary<NSString *, id> *devices;
static NSMutableSet<NSString *> *bulkOwned;
static NSTimer *watchdog;
static BOOL bulkBusy;
static NSUInteger bulkFailures;
static NSString *scanNetwork;
static void (*oldStart)(id, SEL);
extern void NWInvokeRefresh(void *adapter, const void *entry);
static void notify(void) { [NSNotificationCenter.defaultCenter postNotificationName:NWStateChanged object:nil]; }
static void onMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}
static id readObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}
static void setObject(id object, NSString *name, id value) {
    SEL sel = NSSelectorFromString(name);
    if (value && [object respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(object, sel, value);
}
static Class commands(void) { return NSClassFromString(@"_TtC13HarpyReloaded10MCCommands"); }
static uint32_t ipv4(NSString *text) {
    struct in_addr a; return text && inet_pton(AF_INET, text.UTF8String, &a) == 1 ? ntohl(a.s_addr) : 0;
}
static void localNetwork(uint32_t *local, uint32_t *mask, uint32_t *gateway) {
    *local = *mask = 0; *gateway = ipv4(readObject(commands(), @"gatewayIP"));
    struct ifaddrs *first = NULL;
    if (getifaddrs(&first)) return;
    for (struct ifaddrs *p = first; p; p = p->ifa_next) {
        if (!p->ifa_addr || !p->ifa_netmask || strcmp(p->ifa_name, "en0") || p->ifa_addr->sa_family != AF_INET) continue;
        *local = ntohl(((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr);
        *mask = ntohl(((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr);
        break;
    }
    freeifaddrs(first);
}
static NSString *networkIdentity(void) {
    uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
    return [NSString stringWithFormat:@"%u/%u/%u/%@", local, mask, gateway, NWNetworkIdentity()];
}
static BOOL isBlocked(NSString *ip) {
    Class cls = commands(); SEL sel = NSSelectorFromString(@"runningBlocksForIpWithIp:");
    if (![cls respondsToSelector:sel]) return NO;
    id result = ((id (*)(id, SEL, id))objc_msgSend)(cls, sel, ip);
    if (![result isKindOfClass:NSArray.class]) return NO;
    for (id value in result) {
        int pid = [value respondsToSelector:@selector(intValue)] ? [value intValue] : 0;
        if (pid > 1 && (kill(pid, 0) == 0 || errno == EPERM)) return YES;
    }
    return NO;
}
static void updateDeviceState(NSString *ip) {
    id device = devices[ip]; SEL sel = NSSelectorFromString(@"setIsBlocking:");
    BOOL blocked = isBlocked(ip);
    SEL getter = NSSelectorFromString(@"isBlocking");
    if ([device respondsToSelector:sel] && [device respondsToSelector:getter] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(device, getter) != blocked)
        ((void (*)(id, SEL, BOOL))objc_msgSend)(device, sel, blocked);
    if (blocked) [bulkOwned addObject:ip];
    if (!blocked) [bulkOwned removeObject:ip];
}

@interface NWScanSession : NSObject
@property (nonatomic) uint64_t generation;
@property (nonatomic, strong) NWLegacyScanner *scanner;
@property (nonatomic, strong) id adapter;
@property (nonatomic, strong) dispatch_queue_t worker;
@property (nonatomic, copy) NSString *network;
@property (nonatomic) uint32_t localAddress;
@end
static NWScanSession *currentSession;
static void retire(NWScanSession *session) {
    if (!session) return;
    // The native stop method waits for its operation queue. Never call it on main.
    // Serializing start/stop per instance also prevents cancelling a half-built scan.
    dispatch_async(session.worker, ^{
        @try { [session.scanner stop]; }
        @catch (NSException *exception) { NSLog(@"Nuke Wireless: stop failed (%@)", exception.name); }
    });
}
static void finish(uint64_t generation, BOOL success, int status) {
    if (success && ![currentSession.network isEqualToString:networkIdentity()]) success = NO;
    if (!NWStateFinish(&state, generation, success)) return;
    [watchdog invalidate]; watchdog = nil;
    NWScanSession *done = currentSession; currentSession = nil;
    id adapter = done.adapter ?: wifiAdapter;
    if (success) {
        scanNetwork = networkIdentity();
        ((void (*)(id, SEL, int))objc_msgSend)(adapter, NSSelectorFromString(@"lanScanDidFinishScanningWithStatus:"), status);
    } else {
        scanNetwork = nil;
        ((void (*)(id, SEL))objc_msgSend)(adapter, NSSelectorFromString(@"lanScanDidFailedToScan"));
    }
    retire(done);
    NSLog(@"Nuke Wireless: scan %llu ended (%@), %lu rows", (unsigned long long)generation,
          success ? @"complete" : @"failed", (unsigned long)devices.count);
    notify();
}
static void armWatchdog(uint64_t generation) {
    [watchdog invalidate];
    watchdog = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (state.generation != generation || !NWStateBusy(&state)) { [timer invalidate]; return; }
        if (NWStateExpired(&state, CACurrentMediaTime())) finish(generation, NO, 1);
    }];
}
@implementation NWScanSession
- (void)lanScanDidFindNewDevice:(id)device {
    onMain(^{
        if (currentSession != self || !NWStateAccepts(&state, self.generation)) return;
        state.progress = CACurrentMediaTime();
        NSString *ip = readObject(device, @"ipAddress");
        if (!ipv4(ip)) return;
        NSString *name = readObject(device, @"hostname");
        // Match the legacy display rule, so the summary counts exactly the visible rows.
        if (ipv4(ip) == self.localAddress && (!name.length || [name isEqualToString:@"Unknown Host"])) return;
        NSString *vendor = NWVendorForMAC(readObject(device, @"macAddress"));
        if (vendor.length) setObject(device, @"setBrand:", vendor);
        id existing = devices[ip];
        if (existing) {
            for (NSString *property in @[@"hostname", @"macAddress", @"brand", @"subnetMask"]) {
                NSString *value = readObject(device, property);
                if (![value isKindOfClass:NSString.class] || !value.length || [value hasPrefix:@"Unknown"]) continue;
                NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[property substringToIndex:1] uppercaseString], [property substringFromIndex:1]];
                setObject(existing, setter, value);
            }
        } else {
            devices[ip] = device;
            // Preserve both legacy enrichment/alias hooks and the Swift published list.
            ((void (*)(id, SEL, id))objc_msgSend)(self.adapter, NSSelectorFromString(@"lanScanDidFindNewDevice:"), device);
        }
        updateDeviceState(ip); notify();
    });
}
- (void)lanScanDidFinishScanningWithStatus:(int)status {
    onMain(^{ if (currentSession == self) finish(self.generation, status == 0, status); });
}
- (void)lanScanDidFailedToScan {
    onMain(^{ if (currentSession == self) finish(self.generation, NO, 1); });
}
- (void)lanScanProgressPinged:(float)pinged from:(NSInteger)total {
    onMain(^{
        if (currentSession != self || !NWStateAccepts(&state, self.generation)) return;
        state.progress = CACurrentMediaTime();
        SEL sel = NSSelectorFromString(@"lanScanProgressPinged:from:");
        if ([self.adapter respondsToSelector:sel]) ((void (*)(id, SEL, float, NSInteger))objc_msgSend)(self.adapter, sel, pinged, total);
    });
}
@end

static void scannerStarted(NWLegacyScanner *scanner, SEL sel) {
    id adapter = scanner.delegate;
    if (scanner.enableHotspot || [adapter isKindOfClass:NWScanSession.class] ||
        ![adapter isKindOfClass:NSClassFromString(@"_TtC13HarpyReloaded10LanScanner")]) {
        oldStart(scanner, sel); return;
    }
    onMain(^{
        NWScanSession *previous = currentSession; currentSession = nil; retire(previous);
        BOOL pending = state.phase == NWStarting && adapter == wifiAdapter;
        wifiAdapter = adapter;
        if (!pending) NWStateBegin(&state, CACurrentMediaTime());
        state.phase = NWScanning; state.progress = CACurrentMediaTime();
        devices = [NSMutableDictionary new]; scanNetwork = nil;
        NWScanSession *session = [NWScanSession new]; session.generation = state.generation; session.adapter = adapter;
        session.network = networkIdentity();
        uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway); session.localAddress = local;
        session.worker = dispatch_queue_create("app.nukewireless.scan-session", DISPATCH_QUEUE_SERIAL);
        session.scanner = [(NWLegacyScanner *)[NSClassFromString(@"MMLANScanner") alloc] initWithDelegate:session andEnableHotspot:NO];
        currentSession = session; armWatchdog(session.generation); notify();
        if (!session.scanner) { finish(session.generation, NO, 1); return; }
        dispatch_async(session.worker, ^{
            @try { oldStart(session.scanner, @selector(start)); }
            @catch (NSException *exception) {
                NSLog(@"Nuke Wireless: scan exception (%@)", exception.name);
                onMain(^{ if (currentSession == session) finish(session.generation, NO, 1); });
            }
        });
    });
}
BOOL NWScanBusy(void) { return NWStateBusy(&state); }
void NWReconcileDeviceStates(void) {
    if (!NSThread.isMainThread || NWScanBusy() || bulkBusy) return;
    for (NSString *ip in devices.allKeys) updateDeviceState(ip);
}
BOOL NWBulkBusy(void) { return bulkBusy; }
BOOL NWRefreshScan(void) {
    if (!NSThread.isMainThread || NWScanBusy() || bulkBusy || !wifiAdapter) return NO;
    const uint8_t *base = (const uint8_t *)_dyld_get_image_header(0);
    static const uint8_t prologue[] = {0xff,0xc3,0x01,0xd1,0xfa,0x67,0x02,0xa9,0xf8,0x5f,0x03,0xa9,0xf6,0x57,0x04,0xa9};
    if (!base || memcmp(base + 0xc5a8, prologue, sizeof(prologue))) return NO;
    uint64_t generation = NWStateBegin(&state, CACurrentMediaTime());
    [devices removeAllObjects]; scanNetwork = nil; armWatchdog(generation); notify();
    // The pinned Swift refresh clears Published.devices and schedules the anchor's start.
    // The start hook above supplies a NEW underlying scanner and generation-gated delegate.
    NWInvokeRefresh((__bridge void *)wifiAdapter, base + 0xc5a8);
    return YES;
}
NSString *NWScanSummary(void) {
    NSString *message = state.phase == NWIdle ? NWText(@"scan.waiting") :
        (NWScanBusy() ? NWText(@"scan.scanning") : (state.phase == NWFailed ? NWText(@"scan.failed") : NWText(@"scan.finished")));
    return [NSString stringWithFormat:NWText(@"scan.summary"), (unsigned long)devices.count, message,
            bulkFailures ? NWText(@"bulk.partial") : @""];
}
static NSArray<NSDictionary *> *targets(void) {
    uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *ip in [[devices allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id device = devices[ip];
        SEL localSel = NSSelectorFromString(@"isLocalDevice");
        if ([device respondsToSelector:localSel] && ((BOOL (*)(id, SEL))objc_msgSend)(device, localSel)) continue;
        NSString *mac = readObject(device, @"macAddress");
        unsigned int octets[6]; char extra;
        if (mac.length != 17 || sscanf(mac.UTF8String, "%2x:%2x:%2x:%2x:%2x:%2x%c", &octets[0], &octets[1], &octets[2], &octets[3], &octets[4], &octets[5], &extra) != 6) continue;
        uint8_t bytes[6]; for (int i=0;i<6;i++) bytes[i]=(uint8_t)octets[i];
        if (NWEligibleAddress(ipv4(ip), local, mask, gateway, bytes)) [result addObject:@{@"ip":ip,@"mac":mac}];
    }
    return result;
}
static NSArray<NSString *> *activeIPs(void) {
    NSMutableSet *all = [bulkOwned mutableCopy] ?: [NSMutableSet new];
    [all addObjectsFromArray:devices.allKeys];
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *ip in all) if (isBlocked(ip)) [result addObject:ip];
    return [result sortedArrayUsingSelector:@selector(compare:)];
}
NSString *NWBulkTitle(void) {
    if (bulkBusy) return NWText(@"bulk.working");
    return NWText(activeIPs().count ? @"bulk.unblock" : @"bulk.block");
}
static void bulkStep(NSArray<NSDictionary *> *items, NSUInteger index, BOOL unblock, uint64_t generation, NSString *network) {
    if (index >= items.count || (!unblock && (state.generation != generation || ![network isEqualToString:networkIdentity()]))) {
        if (index < items.count) bulkFailures += items.count - index;
        bulkBusy = NO; notify(); return;
    }
    NSString *ip = items[index][@"ip"];
    if (isBlocked(ip) == !unblock) {
        dispatch_async(dispatch_get_main_queue(), ^{ bulkStep(items, index + 1, unblock, generation, network); }); return;
    }
    @try {
        Class cls = commands();
        if (unblock) ((void (*)(id, SEL, id))objc_msgSend)(cls, NSSelectorFromString(@"unblockIPWithIp:"), ip);
        else ((void (*)(id, SEL, id, id))objc_msgSend)(cls, NSSelectorFromString(@"blockGivenIPWithIp:targetMac:"), ip, items[index][@"mac"]);
    } @catch (NSException *exception) { NSLog(@"Nuke Wireless: bulk item exception (%@)", exception.name); }
    // Root-task launch is synchronous in the pinned app; allow process startup before
    // confirming the result. Each failed item is accounted for, then the batch advances.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        BOOL success = isBlocked(ip) == !unblock;
        if (!success) ++bulkFailures;
        if (success && !unblock) [bulkOwned addObject:ip];
        updateDeviceState(ip); notify();
        bulkStep(items, index + 1, unblock, generation, network);
    });
}
void NWConfirmBulk(UIViewController *presenter) {
    if (!NSThread.isMainThread || bulkBusy || !presenter || presenter.presentedViewController) return;
    NSArray<NSString *> *active = activeIPs(); BOOL unblock = active.count > 0;
    if (!unblock && (NWScanBusy() || state.phase != NWComplete || ![scanNetwork isEqualToString:networkIdentity()])) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bulk.block") message:NWText(@"bulk.scanRequired") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil]; return;
    }
    NSMutableArray *items = [NSMutableArray new];
    if (unblock) { for (NSString *ip in active) [items addObject:@{@"ip":ip}]; }
    else [items addObjectsFromArray:targets()];
    if (!items.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bulk.block") message:NWText(@"bulk.empty") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil]; return;
    }
    uint64_t generation = state.generation; NSString *network = [scanNetwork copy]; NSArray *snapshot = [items copy];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(unblock ? @"bulk.unblock" : @"bulk.block") message:[NSString stringWithFormat:NWText(@"bulk.confirm"), (unsigned long)snapshot.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        if (bulkBusy || (!unblock && (state.generation != generation || NWScanBusy() || ![network isEqualToString:networkIdentity()]))) return;
        if (![commands() respondsToSelector:NSSelectorFromString(@"blockGivenIPWithIp:targetMac:")] || ![commands() respondsToSelector:NSSelectorFromString(@"unblockIPWithIp:")]) return;
        bulkBusy = YES; bulkFailures = 0; notify();
        bulkStep(snapshot, 0, unblock, generation, network);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
void NWInstallScanHooks(void) {
    devices = [NSMutableDictionary new]; bulkOwned = [NSMutableSet new];
    Class cls = NSClassFromString(@"MMLANScanner"); Method method = class_getInstanceMethod(cls, @selector(start));
    if (method && !oldStart) oldStart = (void *)method_setImplementation(method, (IMP)scannerStarted);
}
