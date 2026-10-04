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
#import <string.h>
#import <dlfcn.h>
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
static uint32_t configurationGateway(void) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
    });
    if (!framework) return 0;
    CFTypeRef (*create)(CFAllocatorRef, CFStringRef, void *, void *) = dlsym(framework, "SCDynamicStoreCreate");
    CFPropertyListRef (*copyValue)(CFTypeRef, CFStringRef) = dlsym(framework, "SCDynamicStoreCopyValue");
    if (!create || !copyValue) return 0;
    CFTypeRef store = create(NULL, CFSTR("NukeWirelessScan"), NULL, NULL);
    if (!store) return 0;
    id value = CFBridgingRelease(copyValue(store, CFSTR("State:/Network/Global/IPv4")));
    CFRelease(store);
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"PrimaryInterface"] isEqualToString:@"en0"])
        return 0;
    return ipv4(value[@"Router"]);
}
static NSString *networkIdentity(void) {
    uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
    // The scanner invokes this on the main thread during launch. Querying
    // MobileWiFi here can wait on wifid and stall the initial view transition.
    // The interface tuple is sufficient to reject stale scan and bulk results.
    return [NSString stringWithFormat:@"%u/%u", local, mask];
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

static void (*oldFound)(id, SEL, id);
static void (*oldFinished)(id, SEL, int);
static void (*oldFailed)(id, SEL);
static void (*oldProgress)(id, SEL, float, NSInteger);
static void finish(uint64_t generation, BOOL success, int status) {
    if (success && ![scanNetwork isEqualToString:networkIdentity()]) success = NO;
    if (!NWStateFinish(&state, generation, success)) return;
    [watchdog invalidate]; watchdog = nil;
    if (!success) scanNetwork = nil;
    NSLog(@"Nuke Wireless: scan %llu ended (%@), %lu rows", (unsigned long long)generation,
          success ? @"complete" : @"failed", (unsigned long)devices.count);
    (void)status;
    notify();
}
static void armWatchdog(uint64_t generation) {
    [watchdog invalidate];
    watchdog = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (state.generation != generation || !NWStateBusy(&state)) { [timer invalidate]; return; }
        if (NWStateExpired(&state, CACurrentMediaTime())) finish(generation, NO, 1);
    }];
}
static void foundDevice(id adapter, SEL sel, id device) {
    oldFound(adapter, sel, device);
    onMain(^{
        NSString *ip = readObject(device, @"ipAddress");
        if (!ipv4(ip)) return;
        NSString *name = readObject(device, @"hostname");
        NSString *vendor = NWVendorForMAC(readObject(device, @"macAddress"));
        if (vendor.length) setObject(device, @"setBrand:", vendor);
        NSString *suffix = ip.pathExtension;
        NSString *nickname = readObject(device, @"nickName");
        if (!nickname.length && [name isEqualToString:[@"Equipo ." stringByAppendingString:suffix]])
            setObject(device, @"setHostname:", [NSString stringWithFormat:NWText(@"device.fallback"), suffix]);
        NSString *brand = readObject(device, @"brand");
        if ([brand isEqualToString:@"Unknown"] || [brand isEqualToString:@"Unknown Brand"])
            setObject(device, @"setBrand:", NWText(@"device.unknownVendor"));
        // Display placeholders apply to both WiFi and Hotspot; scan ownership does not.
        if (adapter != wifiAdapter || !NWStateAccepts(&state, state.generation)) return;
        state.progress = CACurrentMediaTime();
        uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
        if (ipv4(ip) == local && (!name.length || [name isEqualToString:@"Unknown Host"])) return;
        id existing = devices[ip];
        if (existing) {
            for (NSString *property in @[@"hostname", @"macAddress", @"brand", @"subnetMask"]) {
                NSString *value = readObject(device, property);
                if (![value isKindOfClass:NSString.class] || !value.length || [value hasPrefix:@"Unknown"] ||
                    [value isEqualToString:NWText(@"device.unknownVendor")]) continue;
                NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[property substringToIndex:1] uppercaseString], [property substringFromIndex:1]];
                setObject(existing, setter, value);
            }
        } else {
            devices[ip] = device;
        }
        updateDeviceState(ip); notify();
    });
}
static void finishedScan(id adapter, SEL sel, int status) {
    oldFinished(adapter, sel, status);
    onMain(^{ if (adapter == wifiAdapter) finish(state.generation, status == 0, status); });
}
static void failedScan(id adapter, SEL sel) {
    oldFailed(adapter, sel);
    onMain(^{ if (adapter == wifiAdapter) finish(state.generation, NO, 1); });
}
static void scanProgress(id adapter, SEL sel, float pinged, NSInteger total) {
    if (oldProgress) oldProgress(adapter, sel, pinged, total);
    onMain(^{
        if (adapter != wifiAdapter || !NWStateAccepts(&state, state.generation)) return;
        state.progress = CACurrentMediaTime();
    });
}

static void scannerStarted(NWLegacyScanner *scanner, SEL sel) {
    id adapter = scanner.delegate;
    if (scanner.enableHotspot || ![adapter isKindOfClass:NSClassFromString(@"_TtC13HarpyReloaded10LanScanner")]) {
        oldStart(scanner, sel); return;
    }
    onMain(^{
        BOOL pending = state.phase == NWStarting && adapter == wifiAdapter;
        wifiAdapter = adapter;
        if (!pending) NWStateBegin(&state, CACurrentMediaTime());
        state.phase = NWScanning; state.progress = CACurrentMediaTime();
        devices = [NSMutableDictionary new]; scanNetwork = networkIdentity();
        armWatchdog(state.generation); notify();
    });
    // The caller may wait for start to return while the main thread is loading.
    // Keep the native scanner on its original thread to avoid that startup deadlock.
    @try { oldStart(scanner, sel); }
    @catch (NSException *exception) {
        NSLog(@"Nuke Wireless: native scan start failed (%@)", exception.name);
        onMain(^{ if (adapter == wifiAdapter) finish(state.generation, NO, 1); });
    }
}
BOOL NWScanBusy(void) { return NWStateBusy(&state); }
void NWReconcileDeviceStates(void) {
    if (!NSThread.isMainThread || NWScanBusy() || bulkBusy) return;
    NSMutableSet *known = [bulkOwned mutableCopy]; [known addObjectsFromArray:devices.allKeys];
    for (NSString *ip in known) updateDeviceState(ip);
}
BOOL NWBulkBusy(void) { return bulkBusy; }
NSArray<NSDictionary<NSString *, id> *> *NWDeviceSnapshot(void) {
    NSCAssert(NSThread.isMainThread, @"Device presentation copies belong to main");
    NSMutableArray *snapshot = [NSMutableArray new];
    for (NSString *ip in devices) {
        id device = devices[ip];
        NSMutableDictionary *row = [NSMutableDictionary new];
        for (NSArray *pair in @[@[@"ip", @"ipAddress"], @[@"name", @"hostname"],
                               @[@"mac", @"macAddress"], @[@"vendor", @"brand"]]) {
            id value = readObject(device, pair[1]);
            row[pair[0]] = [value isKindOfClass:NSString.class] ? [value copy] : @"";
        }
        row[@"ip"] = [ip copy];
        id nickname = readObject(device, @"nickName");
        if ([nickname isKindOfClass:NSString.class] && [nickname length]) row[@"name"] = [nickname copy];
        if (![row[@"name"] length]) row[@"name"] = [NSString stringWithFormat:NWText(@"device.fallback"), ip.pathExtension];
        SEL local = NSSelectorFromString(@"isLocalDevice"); // Same getter already used by targets().
        row[@"local"] = @([device respondsToSelector:local] && ((BOOL (*)(id, SEL))objc_msgSend)(device, local));
        row[@"blocked"] = @([bulkOwned containsObject:ip]);
        [snapshot addObject:[row copy]];
    }
    // Stable input order avoids needless table refreshes from dictionary enumeration.
    [snapshot sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"ip"] compare:b[@"ip"]];
    }];
    return [snapshot copy];
}
uint64_t NWDeviceGeneration(void) { return state.generation; }
NSString *NWReadGatewayAddress(void) {
    uint32_t gateway = configurationGateway();
    if (!gateway) return nil;
    struct in_addr address = {.s_addr = htonl(gateway)};
    char text[INET_ADDRSTRLEN];
    return inet_ntop(AF_INET, &address, text, sizeof(text)) ? [NSString stringWithUTF8String:text] : nil;
}
static const uint8_t *appExecutableBase(void) {
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *path = _dyld_get_image_name(index);
        if (!path) continue;
        const char *name = strrchr(path, '/');
        if (name && strcmp(name + 1, "HarpyReloaded") == 0)
            return (const uint8_t *)_dyld_get_image_header(index);
    }
    return NULL;
}
BOOL NWRefreshScan(void) {
    if (!NSThread.isMainThread || NWScanBusy() || bulkBusy || !wifiAdapter) return NO;
    const uint8_t *base = appExecutableBase();
    static const uint8_t prologue[] = {0xff,0xc3,0x01,0xd1,0xfa,0x67,0x02,0xa9,0xf8,0x5f,0x03,0xa9,0xf6,0x57,0x04,0xa9};
    if (!base || memcmp(base + 0xc5a8, prologue, sizeof(prologue))) return NO;
    uint64_t generation = NWStateBegin(&state, CACurrentMediaTime());
    [devices removeAllObjects]; scanNetwork = nil; armWatchdog(generation); notify();
    // The pinned Swift refresh clears Published.devices and schedules its scanner.
    // The start and callback hooks track that native scan without moving start
    // to a different thread or replacing its delegate.
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
    if (!gateway) gateway = configurationGateway();
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
BOOL NWCanRestartForLanguage(void) {
    id registered = readObject(commands(), @"runningBlocksForArp");
    return NSThread.isMainThread && !NWScanBusy() && !bulkBusy &&
        (![registered isKindOfClass:NSArray.class] || [registered count] == 0) && !activeIPs().count;
}
NSString *NWBulkTitle(void) {
    if (bulkBusy) return NWText(@"bulk.working");
    return NWText(bulkOwned.count ? @"bulk.unblock" : @"bulk.block");
}
static void verifyBulkStep(NSArray<NSDictionary *> *items, NSUInteger index, BOOL unblock,
                           uint64_t generation, NSString *network, NSUInteger attempt);
static void bulkStep(NSArray<NSDictionary *> *items, NSUInteger index, BOOL unblock, uint64_t generation, NSString *network) {
    if (index >= items.count || (!unblock && (state.generation != generation || ![network isEqualToString:networkIdentity()]))) {
        if (index < items.count) bulkFailures += items.count - index;
        bulkBusy = NO; notify(); return;
    }
    NSString *ip = items[index][@"ip"];
    if (isBlocked(ip) == !unblock) {
        dispatch_async(dispatch_get_main_queue(), ^{ bulkStep(items, index + 1, unblock, generation, network); }); return;
    }
    // The preserved native process registry has 64 slots. Never launch a task it
    // cannot track and subsequently release; report the remaining items as failures.
    id registered = readObject(commands(), @"runningBlocksForArp");
    if (!unblock && (![registered isKindOfClass:NSArray.class] || [registered count] >= 64)) {
        bulkFailures += items.count - index; bulkBusy = NO; notify(); return;
    }
    @try {
        Class cls = commands();
        if (unblock) ((void (*)(id, SEL, id))objc_msgSend)(cls, NSSelectorFromString(@"unblockIPWithIp:"), ip);
        else ((void (*)(id, SEL, id, id))objc_msgSend)(cls, NSSelectorFromString(@"blockGivenIPWithIp:targetMac:"), ip, items[index][@"mac"]);
    } @catch (NSException *exception) { NSLog(@"Nuke Wireless: bulk item exception (%@)", exception.name); }
    verifyBulkStep(items, index, unblock, generation, network, 0);
}
static void verifyBulkStep(NSArray<NSDictionary *> *items, NSUInteger index, BOOL unblock,
                           uint64_t generation, NSString *network, NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!bulkBusy) return;
        NSString *ip = items[index][@"ip"];
        BOOL success = isBlocked(ip) == !unblock;
        if (!success && attempt < 7) {
            verifyBulkStep(items, index, unblock, generation, network, attempt + 1);
            return;
        }
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
    Class delegate = NSClassFromString(@"_TtC13HarpyReloaded10LanScanner");
    method = class_getInstanceMethod(delegate, NSSelectorFromString(@"lanScanDidFindNewDevice:"));
    if (method && !oldFound) oldFound = (void *)method_setImplementation(method, (IMP)foundDevice);
    method = class_getInstanceMethod(delegate, NSSelectorFromString(@"lanScanDidFinishScanningWithStatus:"));
    if (method && !oldFinished) oldFinished = (void *)method_setImplementation(method, (IMP)finishedScan);
    method = class_getInstanceMethod(delegate, NSSelectorFromString(@"lanScanDidFailedToScan"));
    if (method && !oldFailed) oldFailed = (void *)method_setImplementation(method, (IMP)failedScan);
    method = class_getInstanceMethod(delegate, NSSelectorFromString(@"lanScanProgressPinged:from:"));
    if (method && !oldProgress) oldProgress = (void *)method_setImplementation(method, (IMP)scanProgress);
    NSLog(@"Nuke Wireless: native scan hooks start=%d callbacks=%d/%d/%d", oldStart != NULL,
          oldFound != NULL, oldFinished != NULL, oldFailed != NULL);
}
