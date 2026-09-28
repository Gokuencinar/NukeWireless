#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "NWScanBridge.h"
#import "NWResources.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#include <string.h>
#include <dlfcn.h>
#include <math.h>

__attribute__((used)) static const char buildMarker[] = "NWBuild-rh25.5-dev3";
static NSString *available(NSString *value) {
    return value.length ? value : NWText(@"unavailable");
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

NSString *NWNetworkIdentity(void) {
    NSDictionary *association = currentAssociation();
    return [NSString stringWithFormat:@"%@/%@", association[@"SSID"] ?: @"", association[@"BSSID"] ?: @""];
}
static void showMessage(UIViewController *controller, NSString *message) {
    if (controller.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nuke Wireless" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
static UITableViewCell *textCell(NSString *title, NSString *detail, BOOL link) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title; content.secondaryText = detail;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.adjustsFontForContentSizeCategory = YES;
    content.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
    cell.contentConfiguration = content;
    cell.selectionStyle = link ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
@interface NWAdvancedController : UITableViewController
@property (nonatomic, weak) UILabel *intervalLabel;
@end
@implementation NWAdvancedController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = NWText(@"advanced.title"); self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; return section == 0 ? 1 : 2; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { (void)table; return NWText(section == 0 ? @"interval.explanation" : @"vendors.explanation"); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    if (index.section == 1) {
        UITableViewCell *cell = textCell(NWText(index.row == 0 ? @"vendors.update" : @"vendors.restore"), nil, YES);
        cell.userInteractionEnabled = !NWVendorUpdateBusy();
        if (NWVendorUpdateBusy()) { UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [spinner startAnimating]; cell.accessoryView = spinner; }
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *label = [UILabel new]; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = YES;
    label.text = [NSString stringWithFormat:NWText(@"interval.value"), NWCurrentPacketInterval()]; self.intervalLabel = label;
    UISlider *slider = [UISlider new]; slider.minimumValue = 0.2; slider.maximumValue = 5; slider.value = (float)NWCurrentPacketInterval(); slider.accessibilityLabel = NWText(@"interval.title");
    [slider addTarget:self action:@selector(intervalChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label,slider]]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack]; UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor]]];
    return cell;
}
- (void)intervalChanged:(UISlider *)slider {
    double value = round(slider.value * 10) / 10; NWSetPacketInterval(value);
    self.intervalLabel.text = [NSString stringWithFormat:NWText(@"interval.value"), NWCurrentPacketInterval()];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; if (index.section != 1 || NWVendorUpdateBusy()) return;
    if (index.row == 0) {
        __weak NWAdvancedController *weakSelf = self;
        NWUpdateVendors(^(NSError *error) {
            NWAdvancedController *controller = weakSelf;
            [controller.tableView reloadData];
            if (controller.view.window) showMessage(controller, error.localizedDescription ?: NWText(@"vendors.updated"));
        });
        [table reloadData];
    } else {
        NSError *error; BOOL restored = NWRestoreVendors(&error);
        showMessage(self, restored ? NWText(@"vendors.restored") : error.localizedDescription);
    }
}
@end

@interface NWLicensesController : UITableViewController
@property (nonatomic, strong) NSArray *entries;
@end
@implementation NWLicensesController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"licenses");
    self.entries = [NSArray arrayWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"Acknowledgements" withExtension:@"plist"]] ?: @[];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 100;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return self.entries.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index { (void)table; NSDictionary *entry = self.entries[index.row]; return textCell(entry[@"title"] ?: @"", entry[@"license"], NO); }
@end

@interface NWInfoController : UITableViewController
@property (nonatomic, strong) NSDictionary *values;
@property (nonatomic) NSUInteger requestID;
@end
@implementation NWInfoController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"info.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 65;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; NSUInteger request = ++self.requestID;
    __weak NWInfoController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSDictionary *values = networkDetails();
        dispatch_async(dispatch_get_main_queue(), ^{
            NWInfoController *controller = weakSelf;
            if (!controller || request != controller.requestID) return;
            controller.values = values; [controller.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; return section == 0 ? 1 : (section == 1 ? 4 : (section == 2 ? 6 : 1)); }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { (void)table; return section == 2 ? NWText(@"network.title") : nil; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { (void)table; return section == 2 ? NWText(@"network.copyHint") : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    if (index.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIImageView *avatar = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NWResourceBundle() pathForResource:@"CreditsAvatar" ofType:@"png"]]];
        avatar.contentMode = UIViewContentModeScaleAspectFill; avatar.clipsToBounds = YES; avatar.layer.cornerRadius = 32;
        [NSLayoutConstraint activateConstraints:@[[avatar.widthAnchor constraintEqualToConstant:64],[avatar.heightAnchor constraintEqualToConstant:64]]];
        UILabel *name = [UILabel new]; name.text = @"Gokuencinar GokuEn"; name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; name.adjustsFontForContentSizeCategory = YES; name.numberOfLines = 0;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[avatar,name]]; stack.axis = UILayoutConstraintAxisVertical; stack.alignment = UIStackViewAlignmentCenter; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:stack]; UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor]]]; return cell;
    }
    if (index.section == 1) {
        NSArray *labels = @[@"GitHub · Gokuencinar", @"Buy Me a Coffee", NWText(@"advanced.title"), NWText(@"licenses")];
        UITableViewCell *cell = textCell(labels[index.row], nil, YES); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
    }
    if (index.section == 3) return textCell(NWText(@"version"), @"1.0.25+rh25.5~dev3", NO);
    NSArray *keys = @[@"SSID",@"BSSID",@"IPv4",@"Puerta de enlace",@"Máscara",@"DNS"];
    NSArray *labels = @[@"SSID",@"BSSID",@"IPv4",NWText(@"network.gateway"),NWText(@"network.mask"),@"DNS"];
    UITableViewCell *cell = textCell(labels[index.row], self.values[keys[index.row]] ?: NWText(@"unavailable"), YES);
    cell.accessoryType = UITableViewCellAccessoryNone; cell.accessibilityHint = NWText(@"network.copyHint"); return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section == 1) {
        if (index.row < 2) {
            NSURL *url = [NSURL URLWithString:index.row == 0 ? @"https://github.com/Gokuencinar" : @"https://buymeacoffee.com/gokuen"];
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        } else {
            UIViewController *destination = index.row == 2 ? (UIViewController *)[NWAdvancedController new] : [NWLicensesController new];
            [self.navigationController pushViewController:destination animated:YES];
        }
    } else if (index.section == 2) {
        NSArray *keys = @[@"SSID",@"BSSID",@"IPv4",@"Puerta de enlace",@"Máscara",@"DNS"];
        NSString *value = self.values[keys[index.row]];
        if (value.length && ![value isEqualToString:NWText(@"unavailable")]) {
            UIPasteboard.generalPasteboard.string = value;
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"network.copied"));
        }
    }
}
@end

static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);
static void (*originalDidLayout)(UIViewController *, SEL);
static void (*originalContentInset)(UIScrollView *, SEL, UIEdgeInsets);
static void (*originalLabelText)(UILabel *, SEL, NSString *);
static char wifiInsetKey, baseInsetKey, statusLabelKey;
static char infoOverlayKey;
static __weak UITabBarController *activeTab;
static const NSInteger refreshTag = 90730;
static BOOL installingUI, layingOut;
static void updateWiFi(void);
@interface NWActions : NSObject
- (void)refresh:(id)sender;
- (void)bulk:(id)sender;
- (void)changed:(NSNotification *)notification;
@end
@implementation NWActions
- (void)refresh:(id)sender {
    BOOL started = NWRefreshScan(); updateWiFi();
    if (!started && !NWScanBusy() && !NWBulkBusy()) showMessage(activeTab.selectedViewController, NWText(@"scan.unavailable"));
    if ([sender isKindOfClass:UIRefreshControl.class] && !NWScanBusy()) [(UIRefreshControl *)sender endRefreshing];
}
- (void)bulk:(id)sender { (void)sender; NWConfirmBulk(activeTab.selectedViewController); updateWiFi(); }
- (void)changed:(NSNotification *)notification { (void)notification; updateWiFi(); }
@end
static NWActions *actions;
static UIScrollView *largestScroll(UIView *view) {
    UIScrollView *best = [view isKindOfClass:UIScrollView.class] ? (UIScrollView *)view : nil;
    for (UIView *child in view.subviews) {
        UIScrollView *candidate = largestScroll(child);
        if (candidate.bounds.size.width * candidate.bounds.size.height > best.bounds.size.width * best.bounds.size.height) best = candidate;
    }
    return best;
}
static void bindButton(UIButton *button, SEL action) {
    [button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:actions action:action forControlEvents:UIControlEventTouchUpInside];
}
static void updateWiFi(void) {
    UITabBarController *tab = activeTab;
    if (layingOut || !tab.isViewLoaded || tab.selectedIndex != 0) return;
    layingOut = YES;
    UIView *root = tab.selectedViewController.view;
    UIButton *refresh = (UIButton *)[root viewWithTag:refreshTag];
    refresh.enabled = !NWScanBusy() && !NWBulkBusy();
    [refresh setTitle:NWText(NWScanBusy() ? @"scan.scanning" : @"refresh") forState:UIControlStateNormal];
    if (refresh) [root bringSubviewToFront:refresh];
    UIView *panel = [tab.view viewWithTag:90122];
    if (panel && !panel.hidden) {
        CGRect bar = [tab.tabBar convertRect:tab.tabBar.bounds toView:tab.view];
        panel.frame = CGRectMake(12, CGRectGetMinY(bar) - 116, MAX(0,tab.view.bounds.size.width-24), 108);
        for (UIView *view in panel.subviews) {
            if ([view isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)view;
                objc_setAssociatedObject(label, &statusLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                label.text = NWScanSummary(); CGRect f = label.frame; f.size.width = panel.bounds.size.width-28; label.frame = f;
            } else if ([view isKindOfClass:UIButton.class]) {
                UIButton *button = (UIButton *)view; BOOL isBulk = NO;
                for (id target in button.allTargets) {
                    NSArray *selectors = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
                    if ([selectors containsObject:@"bulkButtonTapped:"] || [selectors containsObject:@"bulk:"]) { isBulk = YES; break; }
                }
                if (isBulk) {
                    bindButton(button,@selector(bulk:)); [button setTitle:NWBulkTitle() forState:UIControlStateNormal];
                    button.enabled = !NWBulkBusy(); button.frame = CGRectMake(12,57,MAX(0,panel.bounds.size.width-118),40);
                } else button.frame = CGRectMake(panel.bounds.size.width-96,57,84,40);
            }
        }
    }
    UIScrollView *scroll = largestScroll(root);
    if (scroll) {
        if (!scroll.refreshControl) scroll.refreshControl = [UIRefreshControl new];
        UIRefreshControl *control = scroll.refreshControl;
        [control removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
        [control addTarget:actions action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
        if (!NWScanBusy()) [control endRefreshing];
        if (panel && !panel.hidden) {
            NSNumber *base = objc_getAssociatedObject(scroll,&baseInsetKey);
            if (!base) { base = @(scroll.contentInset.bottom); objc_setAssociatedObject(scroll,&baseInsetKey,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            CGRect scrollFrame = [scroll convertRect:scroll.bounds toView:root];
            CGRect panelFrame = [panel convertRect:panel.bounds toView:root];
            CGFloat systemInset = scroll.adjustedContentInset.bottom - scroll.contentInset.bottom;
            CGFloat bottom = MAX(base.doubleValue, CGRectGetMaxY(scrollFrame)-CGRectGetMinY(panelFrame)-systemInset+16);
            objc_setAssociatedObject(scroll,&wifiInsetKey,@(bottom),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIEdgeInsets inset = scroll.contentInset; inset.bottom = bottom;
            if (!UIEdgeInsetsEqualToEdgeInsets(inset,scroll.contentInset)) scroll.contentInset = inset;
            UIEdgeInsets indicator = scroll.verticalScrollIndicatorInsets; indicator.bottom = bottom;
            scroll.verticalScrollIndicatorInsets = indicator;
        }
    }
    layingOut = NO;
}
static void installUI(UIViewController *controller) {
    UITabBarController *tab = controller.tabBarController;
    if (!tab && [controller isKindOfClass:UITabBarController.class]) tab = (UITabBarController *)controller;
    if (!tab || installingUI) return;
    activeTab = tab; installingUI = YES;
    if (tab.selectedIndex == 2 && tab.selectedViewController) {
        UIViewController *host = tab.selectedViewController;
        UINavigationController *info = objc_getAssociatedObject(host, &infoOverlayKey);
        if (!info) {
            info = [[UINavigationController alloc] initWithRootViewController:[NWInfoController new]];
            info.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
            UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
            [appearance configureWithOpaqueBackground];
            appearance.backgroundColor = UIColor.systemGroupedBackgroundColor;
            info.navigationBar.standardAppearance = appearance;
            info.navigationBar.scrollEdgeAppearance = appearance;
            [host addChildViewController:info];
            info.view.translatesAutoresizingMaskIntoConstraints = NO;
            [host.view addSubview:info.view];
            [NSLayoutConstraint activateConstraints:@[
                [info.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
                [info.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
                [info.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
                [info.view.trailingAnchor constraintEqualToAnchor:host.view.trailingAnchor]
            ]];
            [info didMoveToParentViewController:host];
            objc_setAssociatedObject(host, &infoOverlayKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [host.view bringSubviewToFront:info.view];
        host.tabBarItem.title = NWText(@"info.title");
    }
    if (tab.selectedIndex == 0) {
        UIView *root = tab.selectedViewController.view;
        if (![root viewWithTag:refreshTag]) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.tag = refreshTag;
            button.configuration = UIButtonConfiguration.tintedButtonConfiguration; button.translatesAutoresizingMaskIntoConstraints = NO;
            bindButton(button,@selector(refresh:)); [root addSubview:button];
            [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-12],[button.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:8],[button.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
        }
    }
    installingUI = NO;
    updateWiFi();
}
static void appeared(UIViewController *controller, SEL sel, BOOL animated) {
    originalViewDidAppear(controller,sel,animated);
    dispatch_async(dispatch_get_main_queue(), ^{ installUI(controller); });
}
static void layout(UIViewController *controller, SEL sel) {
    originalDidLayout(controller,sel);
    if (controller == activeTab || controller == activeTab.selectedViewController) updateWiFi();
    if (activeTab.selectedIndex == 2 && controller == activeTab.selectedViewController) {
        UINavigationController *info = objc_getAssociatedObject(controller, &infoOverlayKey);
        if (info) [controller.view bringSubviewToFront:info.view];
    }
}
static void inset(UIScrollView *scroll, SEL sel, UIEdgeInsets value) {
    NSNumber *minimum = objc_getAssociatedObject(scroll,&wifiInsetKey);
    if (minimum) value.bottom = MAX(value.bottom, minimum.doubleValue);
    originalContentInset(scroll,sel,value);
}
static void labelText(UILabel *label, SEL sel, NSString *value) {
    if (objc_getAssociatedObject(label,&statusLabelKey)) value = NWScanSummary();
    originalLabelText(label,sel,value);
}
__attribute__((constructor)) static void installExtension(void) {
    NWInstallScanHooks();
    // Install UI and task wrappers after both legacy dylib constructors.
    dispatch_async(dispatch_get_main_queue(), ^{
        actions = [NWActions new];
        [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(changed:) name:NWStateChanged object:nil];
        Method method = class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
        originalViewDidAppear = (void *)method_setImplementation(method,(IMP)appeared);
        method = class_getInstanceMethod(UIViewController.class,@selector(viewDidLayoutSubviews));
        originalDidLayout = (void *)method_setImplementation(method,(IMP)layout);
        method = class_getInstanceMethod(UIScrollView.class,@selector(setContentInset:));
        originalContentInset = (void *)method_setImplementation(method,(IMP)inset);
        method = class_getInstanceMethod(UILabel.class,@selector(setText:));
        originalLabelText = (void *)method_setImplementation(method,(IMP)labelText);
        NWInstallPacketIntervalHook();
        // Reconcile actions from the unchanged individual Swift controls too.
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            if (activeTab.selectedIndex == 0 && activeTab.view.window) {
                NWReconcileDeviceStates(); updateWiFi();
            }
        }];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) installUI(window.rootViewController);
        }
    });
}
