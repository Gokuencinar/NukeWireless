#import "NWScanBridge.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#include <string.h>

static __weak id wifiScanner;
static __weak id wifiAdapter;
static NSMutableSet<NSString *> *devices;
static BOOL pendingStart, observedScan;
static BOOL failedScan;
static void (*oldStart)(id, SEL);
static void (*oldFound)(id, SEL, id);
static void (*oldFinished)(id, SEL, int);
static void (*oldFailed)(id, SEL);

static id readObject(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return [object respondsToSelector:sel] ?
        ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}

static BOOL scannerIsWiFi(id scanner) {
    SEL sel = NSSelectorFromString(@"enableHotspot");
    return [scanner respondsToSelector:sel] &&
        !((BOOL (*)(id, SEL))objc_msgSend)(scanner, sel);
}

static void onMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

static void scannerStarted(id scanner, SEL sel) {
    if (scannerIsWiFi(scanner)) {
        id adapter = readObject(scanner, @"delegate");
        onMain(^{
            wifiScanner = scanner;
            wifiAdapter = adapter;
            pendingStart = NO;
            failedScan = NO;
            observedScan = YES;
            devices = [NSMutableSet new];
        });
    }
    oldStart(scanner, sel);
}

static BOOL hiddenLocalEntry(id device, NSString *ip) {
    NSString *host = readObject(device, @"hostname");
    if (host.length && ![host isEqualToString:@"Unknown Host"]) return NO;
    struct ifaddrs *first = NULL;
    BOOL local = NO;
    if (!getifaddrs(&first)) {
        for (struct ifaddrs *item = first; item; item = item->ifa_next) {
            if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET ||
                strcmp(item->ifa_name, "en0")) continue;
            char text[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in *)item->ifa_addr)->sin_addr,
                text, sizeof(text));
            local = [ip isEqualToString:@(text)];
        }
        freeifaddrs(first);
    }
    return local;
}

static void foundDevice(id adapter, SEL sel, id device) {
    onMain(^{
        if (adapter == wifiAdapter) {
            NSString *ip = readObject(device, @"ipAddress");
            if (ip.length) {
                if (hiddenLocalEntry(device, ip) || [devices containsObject:ip]) return;
                [devices addObject:ip];
            }
        }
        oldFound(adapter, sel, device);
    });
}

static void finishedScan(id adapter, SEL sel, int status) {
    onMain(^{
        oldFinished(adapter, sel, status);
        if (adapter == wifiAdapter) pendingStart = NO;
    });
}

static void failedToScan(id adapter, SEL sel) {
    onMain(^{
        oldFailed(adapter, sel);
        if (adapter == wifiAdapter) { pendingStart = NO; failedScan = YES; }
    });
}

BOOL NWScanBusy(void) {
    id scanner = wifiScanner;
    SEL sel = NSSelectorFromString(@"isScanning");
    BOOL scanning = [scanner respondsToSelector:sel] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(scanner, sel);
    NSOperationQueue *queue = readObject(scanner, @"queue");
    return pendingStart || scanning || queue.operationCount > 0;
}

NSString *NWScanSummary(void) {
    if (!observedScan) return @"Esperando al escáner…";
    NSString *suffix = NWScanBusy() ? @" · escaneando…" :
        (failedScan ? @" · escaneo fallido" : @"");
    return [NSString stringWithFormat:@"%lu equipos en la lista%@",
        (unsigned long)devices.count, suffix];
}

static UIScrollView *findRefreshScroll(UIView *view) {
    if ([view isKindOfClass:UIScrollView.class] && ((UIScrollView *)view).refreshControl)
        return (UIScrollView *)view;
    for (UIView *child in view.subviews) {
        UIScrollView *found = findRefreshScroll(child);
        if (found) return found;
    }
    return nil;
}

BOOL NWRefreshScan(UIView *wifiRootView) {
    if (!NSThread.isMainThread || !wifiRootView) return NO;
    UIScrollView *scroll = findRefreshScroll(wifiRootView);
    UIRefreshControl *refresh = scroll.refreshControl;
    if (!refresh || refresh.isRefreshing) return NO;
    [refresh beginRefreshing];
    [refresh sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

void NWInstallScanHooks(void) {
    Class scanner = NSClassFromString(@"MMLANScanner");
    Method start = class_getInstanceMethod(scanner, NSSelectorFromString(@"start"));
    if (start && !oldStart) oldStart = (void *)method_setImplementation(start, (IMP)scannerStarted);
    // Install delegate hooks after the base tweak's constructors, preserving its
    // naming and blocking callbacks underneath our serialized UI updates.
    dispatch_async(dispatch_get_main_queue(), ^{
        Class adapter = NSClassFromString(@"_TtC13HarpyReloaded10LanScanner");
        Method found = class_getInstanceMethod(adapter, NSSelectorFromString(@"lanScanDidFindNewDevice:"));
        Method finished = class_getInstanceMethod(adapter, NSSelectorFromString(@"lanScanDidFinishScanningWithStatus:"));
        Method failed = class_getInstanceMethod(adapter, NSSelectorFromString(@"lanScanDidFailedToScan"));
        if (found) oldFound = (void *)method_setImplementation(found, (IMP)foundDevice);
        if (finished) oldFinished = (void *)method_setImplementation(finished, (IMP)finishedScan);
        if (failed) oldFailed = (void *)method_setImplementation(failed, (IMP)failedToScan);
    });
}
