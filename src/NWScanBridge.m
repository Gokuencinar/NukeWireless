#import "NWScanBridge.h"
#import "NWDiagnosticReport.h"
#import "NWLegacyABI.h"
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
static NSObject *deviceActionToken;
static NSUInteger bulkFailures;
static NSString *scanNetwork;
static __weak NWLegacyScanner *activeScanner;
static NSString *recoveryNetwork;
static unsigned recoveryRetries;
static double networkReadySince;
static NSObject *activeStartToken;
static BOOL nativeStartReturned;
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
static Class commands(void) { return NSClassFromString(@NWLegacyCommandsClass); }
static uint32_t ipv4(NSString *text) {
    struct in_addr a; return text && inet_pton(AF_INET, text.UTF8String, &a) == 1 ? ntohl(a.s_addr) : 0;
}
static void localNetwork(uint32_t *local, uint32_t *mask, uint32_t *gateway) {
    *local = *mask = 0;
    if (gateway) *gateway = ipv4(readObject(commands(), @"gatewayIP"));
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
static unsigned peerDeviceCount(uint32_t local) {
    unsigned count = 0;
    for (NSString *ip in devices) if (ipv4(ip) != local) ++count;
    return count;
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
    uint32_t local, mask; localNetwork(&local, &mask, NULL);
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
static void finish(uint64_t generation, BOOL success, int status, NSString *origin) {
    BOOL networkChanged = success && ![scanNetwork isEqualToString:networkIdentity()];
    if (networkChanged) success = NO;
    if (!NWStateFinish(&state, generation, success)) return;
    state.progress = CACurrentMediaTime();
    [watchdog invalidate]; watchdog = nil;
    if (!success) scanNetwork = nil;
    NSLog(@"Nuke Wireless: scan %llu ended (%@), %lu rows", (unsigned long long)generation,
          success ? @"complete" : @"failed", (unsigned long)devices.count);
    NSMutableDictionary *details = [NWScanDiagnosticSnapshot() mutableCopy]; details[@"native_status"] = @(status);
    details[@"origin"] = origin; details[@"network_changed"] = @(networkChanged);
    NWDiagnosticRecord(@"wifi_scan", success ? (devices.count ? @"passed" : @"empty") : @"failed", details);
    notify();
}
static void armWatchdog(uint64_t generation) {
    [watchdog invalidate];
    watchdog = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (state.generation != generation || !NWStateBusy(&state)) { [timer invalidate]; return; }
        double now = CACurrentMediaTime(); BOOL expired = NWStateExpired(&state, now);
        if (!expired && nativeStartReturned && !activeScanner.queue.operationCount) {
            uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
            expired = NWScanEmptyQueueExpired(&state, now, YES, YES, peerDeviceCount(local));
        }
        if (expired) {
            NWLegacyScanner *scanner = activeScanner;
            finish(generation, NO, 1, @"watchdog");
            // Native stop waits for operations. Never run that wait on main.
            if (scanner) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [scanner stop]; });
        }
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
    onMain(^{ if (adapter == wifiAdapter) finish(state.generation, status == 0, status, @"native_finished"); });
}
static void failedScan(id adapter, SEL sel) {
    oldFailed(adapter, sel);
    onMain(^{ if (adapter == wifiAdapter) finish(state.generation, NO, 1, @"native_failed"); });
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
    if (scanner.enableHotspot || ![adapter isKindOfClass:NSClassFromString(@NWLegacyScannerClass)]) {
        oldStart(scanner, sel); return;
    }
    NSObject *token = [NSObject new];
    onMain(^{
        BOOL pending = state.phase == NWStarting && adapter == wifiAdapter;
        wifiAdapter = adapter;
        activeScanner = scanner;
        activeStartToken = token; nativeStartReturned = NO;
        if (!pending) NWStateBegin(&state, CACurrentMediaTime());
        state.phase = NWScanning; state.progress = CACurrentMediaTime();
        NWDiagnosticRecord(@"wifi_scan", @"running", @{@"generation": @(state.generation)});
        devices = [NSMutableDictionary new]; scanNetwork = networkIdentity();
        armWatchdog(state.generation); notify();
    });
    // The caller may wait for start to return while the main thread is loading.
    // Keep the native scanner on its original thread to avoid that startup deadlock.
    @try { oldStart(scanner, sel); }
    @catch (NSException *exception) {
        NSLog(@"Nuke Wireless: native scan start failed (%@)", exception.name);
        onMain(^{ if (adapter == wifiAdapter) finish(state.generation, NO, 1, @"native_start_exception"); });
    }
    // An empty native queue does not necessarily publish its completion. Do
    // not infer a stalled start until the synchronous setup has returned.
    onMain(^{ if (activeStartToken == token) nativeStartReturned = YES; });
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
        row[@"nickname"] = [nickname isKindOfClass:NSString.class] ? [nickname copy] : @"";
        row[@"generation"] = @(state.generation);
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
static id currentDevice(NSDictionary *row) {
    if (!NSThread.isMainThread || ![row[@"ip"] isKindOfClass:NSString.class] ||
        ![row[@"mac"] isKindOfClass:NSString.class] || ![row[@"generation"] isKindOfClass:NSNumber.class] ||
        [row[@"generation"] unsignedLongLongValue] != state.generation ||
        ![scanNetwork isEqualToString:networkIdentity()]) return nil;
    id device = devices[row[@"ip"]];
    if (!device || ![readObject(device, @"ipAddress") isEqual:row[@"ip"]] ||
        ![(readObject(device, @"macAddress") ?: @"") isEqual:row[@"mac"]]) return nil;
    return device;
}
static BOOL validMethod(Class cls, SEL selector, BOOL classMethod, const char *encoding) {
    Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}
BOOL NWDeviceCanRename(NSDictionary *row) {
    id device = currentDevice(row);
    return device && !bulkBusy && validMethod(object_getClass(device), NSSelectorFromString(@"setNickName:"), NO, "v24@0:8@16");
}
BOOL NWDeviceSetNickname(NSDictionary *row, NSString *nickname) {
    if (!NWDeviceCanRename(row)) return NO;
    id device = currentDevice(row);
    // MMDevice's optional native property accepts nil when clearing a nickname.
    // No second preferences store or substitute device is introduced.
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(device, NSSelectorFromString(@"setNickName:"), nickname);
    } @catch (NSException *exception) { (void)exception; return NO; }
    notify(); return YES;
}
BOOL NWDeviceCanSetBlocked(NSDictionary *row, BOOL blocked) {
    id device = currentDevice(row);
    if (!device || NWScanBusy() || bulkBusy) return NO;
    SEL local = NSSelectorFromString(@"isLocalDevice");
    if (![device respondsToSelector:local] || ((BOOL (*)(id, SEL))objc_msgSend)(device, local)) return NO;
    if (blocked) {
        NSString *mac = readObject(device, @"macAddress");
        NSRegularExpression *format = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$" options:0 error:NULL];
        if (![format firstMatchInString:mac ?: @"" options:0 range:NSMakeRange(0, mac.length)]) return NO;
        id registered = readObject(commands(), @"runningBlocksForArp");
        if (![registered isKindOfClass:NSArray.class] || [registered count] >= 64) return NO;
    }
    return validMethod(commands(), blocked ? NSSelectorFromString(@"blockGivenIPWithIp:targetMac:") :
        NSSelectorFromString(@"unblockIPWithIp:"), YES, blocked ? "v32@0:8@16@24" : "v24@0:8@16");
}
static void verifyDeviceBlock(NSDictionary *row, BOOL blocked, NSObject *token, NSUInteger attempt, void (^completion)(BOOL)) {
    if (deviceActionToken != token) return;
    BOOL success = currentDevice(row) && isBlocked(row[@"ip"]) == blocked;
    if (!success && currentDevice(row) && attempt < 7) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            verifyDeviceBlock(row, blocked, token, attempt + 1, completion);
        }); return;
    }
    if (currentDevice(row)) updateDeviceState(row[@"ip"]);
    deviceActionToken = nil; bulkBusy = NO; notify();
    if (completion) completion(success);
}
BOOL NWDeviceSetBlocked(NSDictionary *row, BOOL blocked, void (^completion)(BOOL success)) {
    if (!NWDeviceCanSetBlocked(row, blocked)) return NO;
    if (isBlocked(row[@"ip"]) == blocked) {
        updateDeviceState(row[@"ip"]); notify(); if (completion) completion(YES); return YES;
    }
    NSObject *token = [NSObject new]; deviceActionToken = token; bulkBusy = YES; notify();
    if (!currentDevice(row)) { deviceActionToken = nil; bulkBusy = NO; notify(); return NO; }
    @try {
        if (blocked) ((void (*)(id, SEL, id, id))objc_msgSend)(commands(), NSSelectorFromString(@"blockGivenIPWithIp:targetMac:"), row[@"ip"], row[@"mac"]);
        else ((void (*)(id, SEL, id))objc_msgSend)(commands(), NSSelectorFromString(@"unblockIPWithIp:"), row[@"ip"]);
    } @catch (NSException *exception) {
        (void)exception; deviceActionToken = nil; bulkBusy = NO; notify(); return NO;
    }
    verifyDeviceBlock([row copy], blocked, token, 0, [completion copy]); return YES;
}
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
        if (name && strcmp(name + 1, NWLegacyExecutable) == 0)
            return (const uint8_t *)_dyld_get_image_header(index);
    }
    return NULL;
}
static BOOL refreshScan(BOOL manual) {
    if (!NSThread.isMainThread || NWScanBusy() || bulkBusy || !wifiAdapter) return NO;
    // Native start stops a previous queue synchronously; wait for it to drain.
    if (activeScanner.queue.operationCount) return NO;
    const uint8_t *base = appExecutableBase();
    static const uint8_t prologue[] = {0xff,0xc3,0x01,0xd1,0xfa,0x67,0x02,0xa9,0xf8,0x5f,0x03,0xa9,0xf6,0x57,0x04,0xa9};
    if (!base || memcmp(base + 0xc5a8, prologue, sizeof(prologue))) return NO;
    if (manual) recoveryRetries = 0;
    uint64_t generation = NWStateBegin(&state, CACurrentMediaTime());
    [devices removeAllObjects]; scanNetwork = nil; armWatchdog(generation); notify();
    // The pinned Swift refresh clears Published.devices and schedules its scanner.
    // The start and callback hooks track that native scan without moving start
    // to a different thread or replacing its delegate.
    NWDiagnosticRecord(@"wifi_scan", @"running", NWScanDiagnosticSnapshot());
    NWInvokeRefresh((__bridge void *)wifiAdapter, base + 0xc5a8);
    return YES;
}
BOOL NWRefreshScan(void) { return refreshScan(YES); }
NSDictionary *NWScanDiagnosticSnapshot(void) {
    uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
    return @{@"phase": @(state.phase), @"generation": @(state.generation),
        @"elapsed_seconds": @(state.started ? MAX(0, CACurrentMediaTime() - state.started) : 0),
        @"device_count": @(devices.count), @"adapter_present": @(wifiAdapter != nil),
        @"native_queue_count": @(activeScanner.queue.operationCount), @"native_start_returned": @(nativeStartReturned),
        @"automatic_retries": @(recoveryRetries), @"ipv4_subnet_ready": @(NWScanInterfaceReady(local, mask)),
        @"hooks": @{@"start": @(oldStart != NULL), @"found": @(oldFound != NULL),
            @"finished": @(oldFinished != NULL), @"failed": @(oldFailed != NULL), @"progress": @(oldProgress != NULL)},
        @"executable_loaded": @(appExecutableBase() != NULL)};
}
void NWMaintainWiFiScan(void) {
    if (!NSThread.isMainThread || !wifiAdapter || bulkBusy ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    uint32_t local, mask, gateway; localNetwork(&local, &mask, &gateway);
    if (!NWScanInterfaceReady(local, mask)) { networkReadySince = 0; return; }
    double now = CACurrentMediaTime(); NSString *network = networkIdentity();
    BOOL changed = ![recoveryNetwork isEqual:network];
    if (changed) { recoveryNetwork = network; recoveryRetries = 0; networkReadySince = now; }
    if (!networkReadySince) networkReadySince = now;
    if (now - networkReadySince < 2 || activeScanner.queue.operationCount || NWScanBusy()) return;
    BOOL movedNetwork = state.phase == NWComplete && scanNetwork && ![scanNetwork isEqual:network];
    if ((!recoveryRetries && movedNetwork) ||
        NWScanRetryAllowed(&state, now, recoveryRetries, peerDeviceCount(local), YES)) {
        if (refreshScan(NO)) ++recoveryRetries;
    }
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
    Class delegate = NSClassFromString(@NWLegacyScannerClass);
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

#ifdef NW_UI_TESTING
extern void NWResetDeviceCommandFixture(void);
extern NSArray *NWDeviceCommandFixtureCalls(void);
static NWScanState browserSavedState;
static NSMutableDictionary *browserSavedDevices;
static NSMutableSet *browserSavedOwned;
static NSString *browserSavedNetwork;
static BOOL browserSavedBusy;
static NSObject *browserSavedActionToken;
void NWBeginDeviceActionsUITest(void) {
    browserSavedState = state; browserSavedDevices = devices; browserSavedOwned = bulkOwned;
    browserSavedNetwork = scanNetwork; browserSavedBusy = bulkBusy; browserSavedActionToken = deviceActionToken;
    state.phase = NWComplete; ++state.generation; bulkBusy = NO; deviceActionToken = nil;
    scanNetwork = networkIdentity(); devices = [NSMutableDictionary new]; bulkOwned = [NSMutableSet new];
    NWResetDeviceCommandFixture();
    for (NSArray *values in @[@[@"Mesa", @"192.0.2.42", @"00:11:22:33:44:55", @"Samsung"],
        @[@"iPhone", @"192.0.2.43", @"00:11:22:33:44:66", @"Apple"]]) {
        id device = [NSClassFromString(@NWLegacyDeviceClass) new];
        setObject(device, @"setHostname:", values[0]); setObject(device, @"setIpAddress:", values[1]);
        setObject(device, @"setMacAddress:", values[2]); setObject(device, @"setBrand:", values[3]);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(device, NSSelectorFromString(@"setIsLocalDevice:"), [values[0] isEqual:@"iPhone"]);
        devices[values[1]] = device;
    }
}
void NWEndDeviceActionsUITest(void) {
    state = browserSavedState; devices = browserSavedDevices; bulkOwned = browserSavedOwned;
    scanNetwork = browserSavedNetwork; bulkBusy = browserSavedBusy; deviceActionToken = browserSavedActionToken;
    NWResetDeviceCommandFixture();
}
int NWDeviceActionsUIRegressionCheck(void) {
    NWBeginDeviceActionsUITest();
    @try {
        NSDictionary *row = NWDeviceSnapshot().firstObject;
        if (!NWDeviceCanRename(row) || !NWDeviceSetNickname(row, @"Escritorio") ||
            ![NWDeviceSnapshot().firstObject[@"name"] isEqual:@"Escritorio"]) return 1;
        if (!NWDeviceSetNickname(row, nil) || ![NWDeviceSnapshot().firstObject[@"name"] isEqual:@"Mesa"]) return 2;
        NSMutableDictionary *stale = [row mutableCopy]; stale[@"generation"] = @(state.generation + 1);
        if (NWDeviceSetNickname(stale, @"Incorrecto") || NWDeviceSetBlocked(stale, YES, nil)) return 3;
        stale = [row mutableCopy]; stale[@"mac"] = @"00:11:22:33:44:99";
        if (NWDeviceSetNickname(stale, @"Incorrecto") || NWDeviceSetBlocked(stale, YES, nil)) return 4;
        __block BOOL completed = NO, success = NO;
        if (!NWDeviceSetBlocked(row, YES, ^(BOOL result) { completed = YES; success = result; }) || !completed || !success) return 5;
        if (![NWDeviceCommandFixtureCalls() isEqual:@[@[@"block", @"192.0.2.42", @"00:11:22:33:44:55"]]] ||
            ![NWDeviceSnapshot().firstObject[@"blocked"] boolValue]) return 6;
        if (!NWDeviceSetBlocked(row, NO, nil) || [NWDeviceSnapshot().firstObject[@"blocked"] boolValue]) return 7;
        if (NWDeviceCanSetBlocked(NWDeviceSnapshot().lastObject, YES)) return 8;
        state.phase = NWScanning;
        if (NWDeviceCanSetBlocked(row, YES)) return 9;
        state.phase = NWComplete; scanNetwork = @"different-network";
        if (NWDeviceSetNickname(row, @"Incorrecto") || NWDeviceSetBlocked(row, YES, nil)) return 10;
        return 0;
    } @finally { NWEndDeviceActionsUITest(); }
}
static NWScanState uiTestSavedScanState;
void NWBeginWiFiScanUITest(void) { uiTestSavedScanState = state; state.phase = NWScanning; }
void NWEndWiFiScanUITest(void) { state = uiTestSavedScanState; }
#endif
