#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "NWScanBridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include <dlfcn.h>

/* Info-only extension for the user's Nuke Wireless 1.0.25 package. */
__attribute__((used)) static const char buildMarker[] = "NWBuild-rh25.3";
static const NSInteger kInfoOverlayTag = 90721;
static const NSInteger kRefreshButtonTag = 90730;
static const NSInteger kNetworkRowTag = 90800;
static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);
static void (*originalDidLayout)(UIViewController *, SEL);
static void (*originalContentSize)(UIScrollView *, SEL, CGSize);
static void (*originalContentInset)(UIScrollView *, SEL, UIEdgeInsets);
static void (*originalScrollEnabled)(UIScrollView *, SEL, BOOL);
static BOOL (*originalCancelTouches)(UIScrollView *, SEL, UIView *);
static void (*originalLabelText)(UILabel *, SEL, NSString *);
static char infoScrollKey, wifiInsetKey, statusLabelKey;
static __weak UITabBarController *activeTab;
static void layoutAdditions(UITabBarController *tab);
static NSArray<NSString *> *networkKeys(void) {
    return @[@"SSID", @"BSSID", @"IPv4", @"Puerta de enlace", @"Máscara", @"DNS"];
}
static void updateNetworkRows(UIView *overlay, NSDictionary<NSString *, NSString *> *values);
static void refreshNetworkRows(UIView *overlay);

@interface NWInfoLinkTarget : NSObject
@property (nonatomic, weak) UIView *overlay;
- (void)openGitHub:(id)sender;
- (void)openCoffee:(id)sender;
- (void)copyNetworkValue:(UIButton *)sender;
- (void)refreshWiFi:(id)sender;
@end

@implementation NWInfoLinkTarget
- (void)openGitHub:(id)sender {
    (void)sender;
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/Gokuencinar"]
                                   options:@{} completionHandler:nil];
}
- (void)openCoffee:(id)sender {
    (void)sender;
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://buymeacoffee.com/gokuen"]
                                   options:@{} completionHandler:nil];
}
- (void)copyNetworkValue:(UIButton *)sender {
    NSString *value = sender.accessibilityValue;
    if (value.length && ![value isEqualToString:@"No disponible"])
        UIPasteboard.generalPasteboard.string = value;
}
- (void)refreshWiFi:(id)sender {
    (void)sender;
    NWRefreshScan();
    layoutAdditions(activeTab);
}
@end

static NWInfoLinkTarget *linkTarget;

static NSString *available(NSString *value) {
    return value.length ? value : @"No disponible";
}

// MobileWiFi reads only the current association on the jailbroken device.
// Every symbol and CoreFoundation type is checked before use.
static NSDictionary *currentAssociation(void) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    });
    if (!framework) return @{};
    CFTypeRef (*create)(CFAllocatorRef, int) = dlsym(framework, "WiFiManagerClientCreate");
    CFArrayRef (*copyDevices)(CFTypeRef) = dlsym(framework, "WiFiManagerClientCopyDevices");
    CFTypeRef (*copyNetwork)(CFTypeRef) = dlsym(framework, "WiFiDeviceClientCopyCurrentNetwork");
    CFStringRef (*getSSID)(CFTypeRef) = dlsym(framework, "WiFiNetworkGetSSID");
    CFTypeRef (*getProperty)(CFTypeRef, CFStringRef) = dlsym(framework, "WiFiNetworkGetProperty");
    CFStringRef (*getInterface)(CFTypeRef) = dlsym(framework, "WiFiDeviceClientGetInterfaceName");
    if (!create || !copyDevices || !copyNetwork || !getSSID || !getProperty) return @{};
    CFTypeRef manager = create(kCFAllocatorDefault, 0);
    if (!manager) return @{};
    CFArrayRef interfaces = copyDevices(manager);
    NSMutableDictionary *result = [NSMutableDictionary new];
    if (interfaces && CFGetTypeID(interfaces) == CFArrayGetTypeID()) {
        for (CFIndex index = 0; index < CFArrayGetCount(interfaces); ++index) {
            CFTypeRef device = CFArrayGetValueAtIndex(interfaces, index);
            CFStringRef name = getInterface ? getInterface(device) : NULL;
            if (name && !CFEqual(name, CFSTR("en0"))) continue;
            CFTypeRef network = copyNetwork(device);
            if (!network) continue;
            CFStringRef ssid = getSSID(network);
            if (ssid && CFGetTypeID(ssid) == CFStringGetTypeID())
                result[@"SSID"] = [(__bridge NSString *)ssid copy];
            CFTypeRef bssid = getProperty(network, CFSTR("BSSID"));
            if (bssid && CFGetTypeID(bssid) == CFStringGetTypeID())
                result[@"BSSID"] = [(__bridge NSString *)bssid copy];
            else if (bssid && CFGetTypeID(bssid) == CFDataGetTypeID() && CFDataGetLength(bssid) == 6) {
                const UInt8 *b = CFDataGetBytePtr(bssid);
                result[@"BSSID"] = [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
                    b[0], b[1], b[2], b[3], b[4], b[5]];
            }
            CFRelease(network);
            if (result.count) break;
        }
    }
    if (interfaces) CFRelease(interfaces);
    CFRelease(manager);
    return result;
}

static void interfaceIPv4(NSString **address, NSString **mask) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return;
    for (struct ifaddrs *entry = interfaces; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || !entry->ifa_name ||
            strcmp(entry->ifa_name, "en0") != 0 ||
            entry->ifa_addr->sa_family != AF_INET) continue;
        char text[INET_ADDRSTRLEN];
        struct sockaddr_in *ip = (struct sockaddr_in *)entry->ifa_addr;
        if (inet_ntop(AF_INET, &ip->sin_addr, text, sizeof(text)))
            *address = [NSString stringWithUTF8String:text];
        if (entry->ifa_netmask) {
            struct sockaddr_in *netmask = (struct sockaddr_in *)entry->ifa_netmask;
            if (inet_ntop(AF_INET, &netmask->sin_addr, text, sizeof(text)))
                *mask = [NSString stringWithUTF8String:text];
        }
        break;
    }
    freeifaddrs(interfaces);
}

static NSDictionary<NSString *, NSString *> *networkDetails(void) {
    NSString *address = nil, *mask = nil;
    interfaceIPv4(&address, &mask);
    NSDictionary *wifi = currentAssociation();
    NSString *ssid = wifi[@"SSID"];
    NSString *bssid = wifi[@"BSSID"];
    NSString *router = nil, *dnsServer = nil;
    static void *systemConfiguration;
    if (!systemConfiguration) systemConfiguration = dlopen(
        "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
    CFTypeRef (*createStore)(CFAllocatorRef, CFStringRef, void *, void *) =
        systemConfiguration ? dlsym(systemConfiguration, "SCDynamicStoreCreate") : NULL;
    CFPropertyListRef (*copyValue)(CFTypeRef, CFStringRef) =
        systemConfiguration ? dlsym(systemConfiguration, "SCDynamicStoreCopyValue") : NULL;
    CFTypeRef store = createStore && copyValue ?
        createStore(NULL, CFSTR("NukeWirelessInfo"), NULL, NULL) : NULL;
    if (store) {
        NSDictionary *globalIPv4 = CFBridgingRelease(copyValue(
            store, CFSTR("State:/Network/Global/IPv4")));
        if ([globalIPv4[@"PrimaryInterface"] isEqualToString:@"en0"])
            router = globalIPv4[@"Router"];
        NSDictionary *globalDNS = CFBridgingRelease(copyValue(
            store, CFSTR("State:/Network/Global/DNS")));
        NSArray *servers = globalDNS[@"ServerAddresses"];
        if ([servers.firstObject isKindOfClass:[NSString class]])
            dnsServer = servers.firstObject;
        CFRelease(store);
    }
    return @{
        @"SSID": available(ssid),
        @"BSSID": available(bssid),
        @"IPv4": available(address),
        @"Puerta de enlace": available(router),
        @"Máscara": available(mask),
        @"DNS": available(dnsServer),
    };
}

static UIScrollView *findInfoScroll(UIView *view, CGFloat *largestArea) {
    UIScrollView *best = nil;
    NSString *className = NSStringFromClass(view.class);
    if ([view isKindOfClass:[UIScrollView class]] &&
        [className containsString:@"HostingScrollView"]) {
        CGFloat area = view.bounds.size.width * view.bounds.size.height;
        if (area > *largestArea) {
            *largestArea = area;
            best = (UIScrollView *)view;
        }
    }
    for (UIView *child in view.subviews) {
        UIScrollView *candidate = findInfoScroll(child, largestArea);
        if (candidate) best = candidate;
    }
    return best;
}

static UILabel *infoLabel(UIView *parent, CGRect frame, NSString *text,
                          CGFloat fontSize, NSTextAlignment alignment, NSInteger tag) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:fontSize];
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    label.tag = tag;
    [parent addSubview:label];
    return label;
}

static void infoButton(UIView *parent, CGRect frame, NSString *title,
                       SEL action, BOOL filled) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    if (filled) {
        button.backgroundColor = UIColor.systemBlueColor;
        button.layer.cornerRadius = 8;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    [button addTarget:linkTarget action:action forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:button];
}

static void updateNetworkRows(UIView *overlay, NSDictionary<NSString *, NSString *> *values) {
    NSArray<NSString *> *keys = networkKeys();
    for (NSUInteger index = 0; index < keys.count; ++index) {
        UIButton *row = (UIButton *)[overlay viewWithTag:kNetworkRowTag + index];
        NSString *value = values[keys[index]] ?: @"No disponible";
        row.accessibilityValue = value;
        UILabel *valueLabel = (UILabel *)[row viewWithTag:1];
        valueLabel.text = value;
    }
}

static void refreshNetworkRows(UIView *overlay) {
    if (!overlay) return;
    __weak UIView *weakOverlay = overlay;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *values = networkDetails();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakOverlay) updateNetworkRows(weakOverlay, values);
        });
    });
}

static void presentWiFi(UIViewController *controller, UITabBarController *tab) {
    (void)controller;
    UIView *view = tab.selectedViewController.view;
    if (!view || [view viewWithTag:kRefreshButtonTag]) return;
    if (!linkTarget) linkTarget = [NWInfoLinkTarget new];
    CGFloat width = view.bounds.size.width;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kRefreshButtonTag;
    button.frame = CGRectMake(width - 125, view.safeAreaInsets.top + 8, 113, 36);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.96];
    button.layer.cornerRadius = 9;
    [button setTitle:@"↻ Actualizar" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:linkTarget action:@selector(refreshWiFi:)
        forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];
}

static void presentInfo(UIViewController *controller) {
    UITabBarController *tab = controller.tabBarController;
    if (!tab && [controller isKindOfClass:[UITabBarController class]])
        tab = (UITabBarController *)controller;
    if (!tab) return;
    activeTab = tab;
    if (tab.selectedIndex == 0) { presentWiFi(controller, tab); return; }
    if (tab.selectedIndex != 2) return;
    CGFloat largestArea = 0;
    UIScrollView *scroll = tab.selectedViewController ?
        findInfoScroll(tab.selectedViewController.view, &largestArea) : nil;
    if (!scroll) scroll = findInfoScroll(controller.view, &largestArea);
    if (!scroll) return;
    objc_setAssociatedObject(scroll, &infoScrollKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    scroll.scrollEnabled = YES;
    scroll.alwaysBounceVertical = YES;
    scroll.canCancelContentTouches = YES;
    scroll.delaysContentTouches = YES;
    UIView *overlay = [scroll viewWithTag:kInfoOverlayTag];
    if (overlay) {
        refreshNetworkRows(overlay);
        return;
    }

    CGFloat width = scroll.bounds.size.width;
    overlay = [[UIView alloc] initWithFrame:CGRectMake(0, 392, width, 548)];
    overlay.tag = kInfoOverlayTag;
    overlay.backgroundColor = UIColor.blackColor;
    [scroll addSubview:overlay];
    CGSize contentSize = scroll.contentSize;
    contentSize.height = MAX(contentSize.height, CGRectGetMaxY(overlay.frame));
    scroll.contentSize = contentSize;
    if (!linkTarget) linkTarget = [NWInfoLinkTarget new];
    linkTarget.overlay = overlay;

    NSString *avatarPath = [[NSBundle mainBundle] pathForResource:@"CreditsAvatar" ofType:@"jpg"];
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake((width - 62) / 2, 8, 62, 62)];
    avatar.image = [UIImage imageWithContentsOfFile:avatarPath];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 31;
    [overlay addSubview:avatar];

    infoLabel(overlay, CGRectMake(15, 72, width - 30, 40),
        @"Gokuencinar GokuEn", 16,
        NSTextAlignmentCenter, 0);
    infoButton(overlay, CGRectMake(35, 114, width - 70, 30),
        @"GitHub: @Gokuencinar", @selector(openGitHub:), NO);
    infoButton(overlay, CGRectMake(35, 148, width - 70, 36),
        @"Buy Me a Coffee", @selector(openCoffee:), YES);
    infoLabel(overlay, CGRectMake(18, 193, width - 36, 27),
        @"Red actual", 18, NSTextAlignmentLeft, 0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 228, width - 32, 300)];
    card.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    card.layer.cornerRadius = 13;
    card.clipsToBounds = YES;
    [overlay addSubview:card];
    NSArray<NSString *> *keys = networkKeys();
    for (NSUInteger index = 0; index < keys.count; ++index) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.tag = kNetworkRowTag + index;
        row.frame = CGRectMake(0, index * 50, card.bounds.size.width, 50);
        row.accessibilityLabel = keys[index];
        [row addTarget:linkTarget action:@selector(copyNetworkValue:)
            forControlEvents:UIControlEventTouchUpInside];
        infoLabel(row, CGRectMake(12, 4, card.bounds.size.width - 24, 17),
            keys[index], 11, NSTextAlignmentLeft, 0).textColor = UIColor.lightGrayColor;
        UILabel *value = infoLabel(row,
            CGRectMake(12, 21, card.bounds.size.width - 24, 24),
            @"No disponible", 15, NSTextAlignmentLeft, 1);
        value.userInteractionEnabled = NO;
        if (index + 1 < keys.count) {
            UIView *separator = [[UIView alloc] initWithFrame:
                CGRectMake(12, 49, card.bounds.size.width - 24, 1)];
            separator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
            [row addSubview:separator];
        }
        [card addSubview:row];
    }
    refreshNetworkRows(overlay);
}

static void patchedViewDidAppear(UIViewController *controller, SEL selector, BOOL animated) {
    originalViewDidAppear(controller, selector, animated);
    __weak UIViewController *weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongController = weakController;
        if (strongController) {
            presentInfo(strongController);
            layoutAdditions(activeTab);
        }
    });
}

static UIScrollView *findWiFiScroll(UIView *view, CGFloat *area) {
    UIScrollView *best = nil;
    if ([view isKindOfClass:UIScrollView.class]) {
        CGFloat size = view.bounds.size.width * view.bounds.size.height;
        if (size > *area) { *area = size; best = (UIScrollView *)view; }
    }
    for (UIView *child in view.subviews) {
        UIScrollView *found = findWiFiScroll(child, area);
        if (found) best = found;
    }
    return best;
}

static void layoutAdditions(UITabBarController *tab) {
    if (!tab || !tab.isViewLoaded) return;
    UIView *root = tab.selectedViewController.view;
    if (tab.selectedIndex == 2) {
        CGFloat area = 0;
        UIScrollView *scroll = findInfoScroll(root, &area);
        UIView *overlay = [scroll viewWithTag:kInfoOverlayTag];
        if (!overlay) return;
        scroll.scrollEnabled = YES;
        scroll.panGestureRecognizer.enabled = YES;
        scroll.canCancelContentTouches = YES;
        CGSize size = scroll.contentSize;
        size.height = MAX(size.height, CGRectGetMaxY(overlay.frame) + 24);
        if (!CGSizeEqualToSize(scroll.contentSize, size)) scroll.contentSize = size;
        [scroll bringSubviewToFront:overlay];
        return;
    }
    if (tab.selectedIndex != 0) return;
    UIButton *button = (UIButton *)[root viewWithTag:kRefreshButtonTag];
    BOOL busy = NWScanBusy();
    button.enabled = !busy;
    NSString *title = busy ? @"Escaneando…" : @"↻ Actualizar";
    if (![button.currentTitle isEqualToString:title])
        [button setTitle:title forState:UIControlStateNormal];
    if (button) [root bringSubviewToFront:button];
    CGFloat area = 0;
    UIScrollView *scroll = findWiFiScroll(root, &area);
    UIView *panel = [tab.view viewWithTag:90122];
    if (scroll && panel && !panel.hidden) {
        CGRect banner = [panel convertRect:panel.bounds toView:scroll];
        CGFloat bottom = MAX(0, CGRectGetMaxY(scroll.bounds) - CGRectGetMinY(banner) + 16);
        objc_setAssociatedObject(scroll, &wifiInsetKey, @(bottom), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIEdgeInsets inset = scroll.contentInset;
        if (inset.bottom < bottom) { inset.bottom = bottom; scroll.contentInset = inset; }
        UIEdgeInsets indicator = scroll.verticalScrollIndicatorInsets;
        indicator.bottom = bottom;
        if (!UIEdgeInsetsEqualToEdgeInsets(scroll.verticalScrollIndicatorInsets, indicator))
            scroll.verticalScrollIndicatorInsets = indicator;
        UIRefreshControl *refresh = scroll.refreshControl;
        if (refresh) {
            [refresh removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
            [refresh addTarget:linkTarget action:@selector(refreshWiFi:)
                forControlEvents:UIControlEventValueChanged];
            if (!busy) [refresh endRefreshing];
        }
    }
    for (UIView *child in panel.subviews) {
        if ([child isKindOfClass:UILabel.class]) {
            objc_setAssociatedObject(child, &statusLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((UILabel *)child).text = NWScanSummary();
            break;
        }
    }
}

static void patchedDidLayout(UIViewController *controller, SEL selector) {
    originalDidLayout(controller, selector);
    if (activeTab && (controller == activeTab || controller == activeTab.selectedViewController))
        layoutAdditions(activeTab);
}

static void patchedContentSize(UIScrollView *scroll, SEL sel, CGSize size) {
    if (objc_getAssociatedObject(scroll, &infoScrollKey)) {
        UIView *overlay = [scroll viewWithTag:kInfoOverlayTag];
        if (overlay) size.height = MAX(size.height, CGRectGetMaxY(overlay.frame) + 24);
    }
    originalContentSize(scroll, sel, size);
}

static void patchedContentInset(UIScrollView *scroll, SEL sel, UIEdgeInsets inset) {
    NSNumber *minimum = objc_getAssociatedObject(scroll, &wifiInsetKey);
    if (minimum) inset.bottom = MAX(inset.bottom, minimum.doubleValue);
    originalContentInset(scroll, sel, inset);
}

static void patchedScrollEnabled(UIScrollView *scroll, SEL sel, BOOL enabled) {
    originalScrollEnabled(scroll, sel,
        objc_getAssociatedObject(scroll, &infoScrollKey) ? YES : enabled);
}

static BOOL patchedCancelTouches(UIScrollView *scroll, SEL sel, UIView *view) {
    if (objc_getAssociatedObject(scroll, &infoScrollKey)) return YES;
    return originalCancelTouches(scroll, sel, view);
}

static void patchedLabelText(UILabel *label, SEL sel, NSString *text) {
    if (!objc_getAssociatedObject(label, &statusLabelKey)) {
        originalLabelText(label, sel, text);
        return;
    }
    NSString *value = NWScanSummary();
    if (![label.text isEqualToString:value]) originalLabelText(label, sel, value);
}

__attribute__((constructor)) static void installInfoExtension(void) {
    Method method = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
    if (method) originalViewDidAppear = (void *)method_setImplementation(
        method, (IMP)patchedViewDidAppear);
    method = class_getInstanceMethod(UIViewController.class, @selector(viewDidLayoutSubviews));
    originalDidLayout = (void *)method_setImplementation(method, (IMP)patchedDidLayout);
    method = class_getInstanceMethod(UIScrollView.class, @selector(setContentSize:));
    originalContentSize = (void *)method_setImplementation(method, (IMP)patchedContentSize);
    method = class_getInstanceMethod(UIScrollView.class, @selector(setContentInset:));
    originalContentInset = (void *)method_setImplementation(method, (IMP)patchedContentInset);
    method = class_getInstanceMethod(UIScrollView.class, @selector(setScrollEnabled:));
    originalScrollEnabled = (void *)method_setImplementation(method, (IMP)patchedScrollEnabled);
    method = class_getInstanceMethod(UIScrollView.class, @selector(touchesShouldCancelInContentView:));
    originalCancelTouches = (void *)method_setImplementation(method, (IMP)patchedCancelTouches);
    method = class_getInstanceMethod(UILabel.class, @selector(setText:));
    originalLabelText = (void *)method_setImplementation(method, (IMP)patchedLabelText);
    NWInstallScanHooks();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
                layoutAdditions(activeTab);
        }];
    });
}
