#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include <dlfcn.h>

/* Info-only extension for the user's Nuke Wireless 1.0.25 package. */
static const NSInteger kInfoOverlayTag = 90721;
static const NSInteger kRefreshButtonTag = 90730;
static const NSInteger kNetworkRowTag = 90800;
static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);
static NSArray<NSString *> *networkKeys(void) {
    return @[@"SSID", @"BSSID", @"IPv4", @"Puerta de enlace", @"Máscara", @"DNS"];
}
static void updateNetworkRows(UIView *overlay, NSDictionary<NSString *, NSString *> *values);
static void refreshNetworkRows(UIView *overlay);

@interface NWInfoLinkTarget : NSObject <CLLocationManagerDelegate>
@property (nonatomic, weak) UIView *overlay;
@property (nonatomic, strong) CLLocationManager *locationManager;
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
    if (value.length && ![value isEqualToString:@"No disponible"] &&
        ![value isEqualToString:@"Ubicación no autorizada"])
        UIPasteboard.generalPasteboard.string = value;
}
- (void)refreshWiFi:(id)sender {
    Class targetClass = NSClassFromString(@"NukeWirelessBulkButtonTarget");
    id target = targetClass ? [targetClass new] : nil;
    SEL refresh = NSSelectorFromString(@"refreshTriggered:");
    if ([target respondsToSelector:refresh])
        ((void (*)(id, SEL, id))objc_msgSend)(target, refresh, sender);
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    (void)manager;
    if (self.overlay) refreshNetworkRows(self.overlay);
}
@end

static NWInfoLinkTarget *linkTarget;

static NSString *available(NSString *value) {
    return value.length ? value : @"No disponible";
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
    NSDictionary *wifi = CFBridgingRelease(CNCopyCurrentNetworkInfo(CFSTR("en0")));
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
    CLAuthorizationStatus location = [CLLocationManager authorizationStatus];
    NSString *missingWiFi = (location == kCLAuthorizationStatusDenied ||
        location == kCLAuthorizationStatusRestricted) ?
        @"Ubicación no autorizada" : @"No disponible";
    return @{
        @"SSID": ssid.length ? ssid : missingWiFi,
        @"BSSID": bssid.length ? bssid : missingWiFi,
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
    updateNetworkRows(overlay, networkDetails());
    __weak UIView *weakOverlay = overlay;
    [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork *network) {
        UIView *current = weakOverlay;
        if (!current || !network) return;
        NSMutableDictionary *values = [networkDetails() mutableCopy];
        if (network.SSID.length) values[@"SSID"] = network.SSID;
        if (network.BSSID.length) values[@"BSSID"] = network.BSSID;
        updateNetworkRows(current, values);
    }];
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
    if (tab.selectedIndex == 0) { presentWiFi(controller, tab); return; }
    if (tab.selectedIndex != 2) return;
    CGFloat largestArea = 0;
    UIScrollView *scroll = tab.selectedViewController ?
        findInfoScroll(tab.selectedViewController.view, &largestArea) : nil;
    if (!scroll) scroll = findInfoScroll(controller.view, &largestArea);
    if (!scroll) return;
    UIView *overlay = [scroll viewWithTag:kInfoOverlayTag];
    if (overlay) {
        refreshNetworkRows(overlay);
        return;
    }

    CGFloat width = scroll.bounds.size.width;
    overlay = [[UIControl alloc] initWithFrame:CGRectMake(0, 392, width, 548)];
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
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        linkTarget.locationManager = [CLLocationManager new];
        linkTarget.locationManager.delegate = linkTarget;
        [linkTarget.locationManager requestWhenInUseAuthorization];
    }
}

static void patchedViewDidAppear(UIViewController *controller, SEL selector, BOOL animated) {
    originalViewDidAppear(controller, selector, animated);
    __weak UIViewController *weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongController = weakController;
        if (strongController) presentInfo(strongController);
    });
}

__attribute__((constructor)) static void installInfoExtension(void) {
    Method method = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
    if (method) originalViewDidAppear = (void *)method_setImplementation(
        method, (IMP)patchedViewDidAppear);
}
