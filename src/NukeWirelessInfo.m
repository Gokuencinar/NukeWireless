#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <objc/runtime.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <dispatch/dispatch.h>
#include <string.h>

/* Info-only extension for the user's Nuke Wireless 1.0.25 package. */
static const NSInteger kInfoOverlayTag = 90721;
static const NSInteger kNetworkLabelTag = 90722;
static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);

@interface NWInfoLinkTarget : NSObject
- (void)openGitHub:(id)sender;
- (void)openCoffee:(id)sender;
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

static NSString *networkDetails(void) {
    NSString *address = nil, *mask = nil;
    interfaceIPv4(&address, &mask);
    if (!address) return @"Wi-Fi: sin conexión IPv4";

    NSDictionary *wifi = CFBridgingRelease(CNCopyCurrentNetworkInfo(CFSTR("en0")));
    NSString *ssid = wifi[@"SSID"];
    NSString *bssid = wifi[@"BSSID"];
    NSString *router = nil, *dnsServer = nil;
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("NukeWirelessInfo"), NULL, NULL);
    if (store) {
        NSDictionary *globalIPv4 = CFBridgingRelease(SCDynamicStoreCopyValue(
            store, CFSTR("State:/Network/Global/IPv4")));
        if ([globalIPv4[@"PrimaryInterface"] isEqualToString:@"en0"])
            router = globalIPv4[@"Router"];
        NSDictionary *globalDNS = CFBridgingRelease(SCDynamicStoreCopyValue(
            store, CFSTR("State:/Network/Global/DNS")));
        NSArray *servers = globalDNS[@"ServerAddresses"];
        if ([servers.firstObject isKindOfClass:[NSString class]])
            dnsServer = servers.firstObject;
        CFRelease(store);
    }
    return [NSString stringWithFormat:
        @"SSID: %@\nBSSID: %@\nIPv4: %@\nPuerta de enlace: %@\nMáscara: %@\nDNS: %@",
        available(ssid), available(bssid), address, available(router),
        available(mask), available(dnsServer)];
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

static void presentInfo(UIViewController *controller) {
    UITabBarController *tab = controller.tabBarController;
    if (!tab && [controller isKindOfClass:[UITabBarController class]])
        tab = (UITabBarController *)controller;
    if (!tab || tab.selectedIndex != 2) return;
    CGFloat largestArea = 0;
    UIScrollView *scroll = tab.selectedViewController ?
        findInfoScroll(tab.selectedViewController.view, &largestArea) : nil;
    if (!scroll) scroll = findInfoScroll(controller.view, &largestArea);
    if (!scroll) return;
    UIView *overlay = [scroll viewWithTag:kInfoOverlayTag];
    if (overlay) {
        UILabel *network = (UILabel *)[overlay viewWithTag:kNetworkLabelTag];
        network.text = networkDetails();
        return;
    }

    CGFloat width = scroll.bounds.size.width;
    overlay = [[UIView alloc] initWithFrame:CGRectMake(0, 392, width, 1800)];
    overlay.tag = kInfoOverlayTag;
    overlay.backgroundColor = UIColor.blackColor;
    [scroll addSubview:overlay];
    if (!linkTarget) linkTarget = [NWInfoLinkTarget new];

    NSString *avatarPath = [[NSBundle mainBundle] pathForResource:@"CreditsAvatar" ofType:@"jpg"];
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:CGRectMake((width - 62) / 2, 8, 62, 62)];
    avatar.image = [UIImage imageWithContentsOfFile:avatarPath];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 31;
    [overlay addSubview:avatar];

    infoLabel(overlay, CGRectMake(15, 72, width - 30, 40),
        @"Adaptación RootHide por Gokuencinar · GokuEn", 15,
        NSTextAlignmentCenter, 0);
    infoButton(overlay, CGRectMake(35, 114, width - 70, 30),
        @"GitHub: @Gokuencinar", @selector(openGitHub:), NO);
    infoButton(overlay, CGRectMake(35, 148, width - 70, 36),
        @"Buy Me a Coffee", @selector(openCoffee:), YES);
    infoLabel(overlay, CGRectMake(18, 190, width - 36, 24),
        @"RED ACTUAL", 15, NSTextAlignmentLeft, 0);
    infoLabel(overlay, CGRectMake(18, 216, width - 36, 146),
        networkDetails(), 13, NSTextAlignmentLeft, kNetworkLabelTag);
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
