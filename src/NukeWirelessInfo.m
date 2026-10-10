#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "NWScanBridge.h"
#import "NWResources.h"
#import "NWLanguage.h"
#import "NWAppearance.h"
#import "NWDeviceBrowser.h"
#import "NWDeviceActions.h"
#import "NWHotspot.h"
#import "NWBluetooth.h"
#import "NWDiagnostics.h"
#import "NWBuild.h"
#import "NWLegacyABI.h"
#import "NWMainTabs.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#include <string.h>
#include <dlfcn.h>
#include <math.h>
#include <syslog.h>
#include <stdlib.h>

__attribute__((used)) static const char buildMarker[] = NW_BUILD_MARKER;
@interface NWGridBackground : UIView
@end
@implementation NWGridBackground
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO; self.accessibilityElementsHidden = YES;
        self.opaque = YES; self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous]; [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    [NWCanvasColor() setFill]; UIRectFill(rect);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, [NWAccentColor() colorWithAlphaComponent:0.055].CGColor);
    CGContextSetLineWidth(context, 0.5);
    for (CGFloat x = 0; x < self.bounds.size.width; x += 32) {
        CGContextMoveToPoint(context, x, 0); CGContextAddLineToPoint(context, x, self.bounds.size.height);
    }
    for (CGFloat y = 0; y < self.bounds.size.height; y += 32) {
        CGContextMoveToPoint(context, 0, y); CGContextAddLineToPoint(context, self.bounds.size.width, y);
    }
    CGContextStrokePath(context);
}
@end
static void styleWiFiCell(UIView *cell) {
    cell.layer.cornerRadius = 12;
    cell.layer.borderWidth = 0.6;
    cell.layer.borderColor = [NWAccentColor() colorWithAlphaComponent:0.24].CGColor;
    cell.tintColor = NWAccentColor();
}
static void styleWiFiLists(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        if (![table.backgroundView isKindOfClass:NWGridBackground.class]) table.backgroundView = [[NWGridBackground alloc] initWithFrame:table.bounds];
        table.backgroundColor = NWCanvasColor(); table.tintColor = NWAccentColor();
        [table.backgroundView setNeedsDisplay];
        table.separatorColor = [NWAccentColor() colorWithAlphaComponent:0.15];
        for (UITableViewCell *cell in table.visibleCells) styleWiFiCell(cell);
    } else if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *list = (UICollectionView *)view;
        if (![list.backgroundView isKindOfClass:NWGridBackground.class]) list.backgroundView = [[NWGridBackground alloc] initWithFrame:list.bounds];
        list.backgroundColor = NWCanvasColor(); list.tintColor = NWAccentColor();
        [list.backgroundView setNeedsDisplay];
        for (UICollectionViewCell *cell in list.visibleCells) styleWiFiCell(cell);
    }
    for (UIView *child in view.subviews) styleWiFiLists(child);
}
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

static void showMessage(UIViewController *controller, NSString *message) {
    if (controller.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NW_BUILD_NAME message:message preferredStyle:UIAlertControllerStyleAlert];
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
    NWStyleCell(cell);
    cell.selectionStyle = link ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
// Presentation only: these helpers do not attach targets or alter row actions.
static void decorateCell(UITableViewCell *cell, NSString *symbol, BOOL networkValue) {
    id configuration = cell.contentConfiguration;
    if (![configuration isKindOfClass:UIListContentConfiguration.class]) return;
    UIListContentConfiguration *content = [configuration copy];
    UIImageSymbolConfiguration *iconStyle = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium];
    content.image = [UIImage systemImageNamed:symbol withConfiguration:iconStyle];
    content.imageProperties.tintColor = NWAccentColor();
    content.imageToTextPadding = 14;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    if (networkValue) {
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        content.textProperties.color = UIColor.secondaryLabelColor;
        content.secondaryTextProperties.font = [UIFontMetrics.defaultMetrics scaledFontForFont:
            [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium]];
        content.secondaryTextProperties.color = UIColor.labelColor;
        content.textToSecondaryTextVerticalPadding = 5;
    }
    cell.contentConfiguration = content;
}
@interface NWAdvancedController : UITableViewController
@property (nonatomic, weak) UILabel *intervalLabel;
@end
@implementation NWAdvancedController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = NWText(@"advanced.title"); self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70; self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor(); }
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
    cell.selectionStyle = UITableViewCellSelectionStyleNone; NWStyleCell(cell);
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

@interface NWInfoController : UITableViewController
@property (nonatomic, strong) NSDictionary *values;
@property (nonatomic) NSUInteger requestID;
- (void)chooseLanguage;
@end
@implementation NWInfoController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"info.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 65;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    self.tableView.backgroundColor = NWCanvasColor();
    self.tableView.tintColor = NWAccentColor();
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; NSUInteger request = ++self.requestID;
    __weak NWInfoController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSDictionary *values = networkDetails();
        dispatch_async(dispatch_get_main_queue(), ^{
            NWInfoController *controller = weakSelf;
            if (!controller || request != controller.requestID) return;
            controller.values = values;
            UITableView *table = controller.tableView;
            CGPoint position = table.contentOffset;
            [UIView performWithoutAnimation:^{
                [table reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
                [table layoutIfNeeded];
                table.contentOffset = position;
            }];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; return section == 0 ? 1 : (section == 1 ? 6 : (section == 2 ? 6 : 1)); }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { (void)table; return section == 2 ? NWText(@"network.title") : nil; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { (void)table; return section == 2 ? NWText(@"network.copyHint") : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    if (index.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone; NWStyleCell(cell);
        UIImageView *avatar = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NWResourceBundle() pathForResource:@"CreditsAvatar" ofType:@"png"]]];
        avatar.contentMode = UIViewContentModeScaleAspectFill; avatar.clipsToBounds = YES; avatar.layer.cornerRadius = 20; avatar.layer.borderWidth = 1; avatar.layer.borderColor = UIColor.separatorColor.CGColor;
        [NSLayoutConstraint activateConstraints:@[[avatar.widthAnchor constraintEqualToConstant:40],[avatar.heightAnchor constraintEqualToConstant:40]]];
        UILabel *name = [UILabel new]; name.text = @"GokuEn"; name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; name.adjustsFontForContentSizeCategory = YES; name.numberOfLines = 0;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[avatar,name]]; stack.axis = UILayoutConstraintAxisHorizontal; stack.alignment = UIStackViewAlignmentCenter; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:stack]; UILayoutGuide *g = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor]]]; return cell;
    }
    if (index.section == 1) {
        NSArray *labels = @[@"GitHub · GokuEn", NWText(@"coffee.title"), NWText(@"advanced.title"), NWText(@"language.title"), NWText(@"appearance.title"), NWText(@"diag.title")];
        NSString *detail = index.row == 3 ? ([NWLanguageCode() isEqualToString:@"es"] ? @"Español" : @"English") :
            (index.row == 4 ? NWText([@"appearance." stringByAppendingString:NWAccentName()]) : nil);
        UITableViewCell *cell = textCell(labels[index.row], detail, YES);
        NSArray *symbols = @[@"chevron.left.forwardslash.chevron.right", @"cup.and.saucer.fill", @"slider.horizontal.3", @"globe", @"paintpalette", @"stethoscope"];
        decorateCell(cell, symbols[index.row], NO);
        if (index.row == 5) cell.accessibilityIdentifier = @"nw.info.diagnostics";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
    }
    if (index.section == 3) {
        UITableViewCell *cell = textCell(NWText(@"version"), [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: NW_BUILD_VERSION, NO);
        decorateCell(cell, @"app.badge", NO); return cell;
    }
    NSArray *keys = @[@"SSID",@"BSSID",@"IPv4",@"Puerta de enlace",@"Máscara",@"DNS"];
    NSArray *labels = @[@"SSID",@"BSSID",@"IPv4",NWText(@"network.gateway"),NWText(@"network.mask"),@"DNS"];
    UITableViewCell *cell = textCell(labels[index.row], self.values[keys[index.row]] ?: NWText(@"unavailable"), YES);
    NSArray *symbols = @[@"wifi", @"antenna.radiowaves.left.and.right", @"number", @"arrow.triangle.branch", @"square.split.2x2", @"network"];
    decorateCell(cell, symbols[index.row], YES);
    cell.accessoryType = UITableViewCellAccessoryNone; cell.accessibilityHint = NWText(@"network.copyHint"); return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section == 1) {
        if (index.row < 2) {
            NSURL *url = [NSURL URLWithString:index.row == 0 ? @"https://github.com/Gokuencinar" : @"https://buymeacoffee.com/gokuen"];
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        } else if (index.row == 2) {
            [self.navigationController pushViewController:[NWAdvancedController new] animated:YES];
        } else if (index.row == 3) {
            [self chooseLanguage];
        } else if (index.row == 4) {
            [self.navigationController pushViewController:NWAppearanceSettingsController() animated:YES];
        } else if (index.row == 5) {
            [self.navigationController pushViewController:NWDiagnosticsController() animated:YES];
        }
    } else if (index.section == 2) {
        NSArray *keys = @[@"SSID",@"BSSID",@"IPv4",@"Puerta de enlace",@"Máscara",@"DNS"];
        NSString *value = self.values[keys[index.row]];
        if (value.length && ![value isEqualToString:NWText(@"unavailable")]) {
            UIPasteboard.generalPasteboard.string = value;
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"network.copied"));
            showMessage(self, NWText(@"network.copied"));
        }
    }
}
- (void)chooseLanguage {
    if (!NWCanRestartForLanguage() || NWBluetoothBusy()) { showMessage(self, NWText(@"language.busy")); return; }
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:NWText(@"language.title")
        message:NWText(@"language.restartHint") preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *code in @[@"es", @"en"]) {
        NSString *name = [code isEqualToString:@"es"] ? @"Español" : @"English";
        if ([code isEqualToString:NWLanguageCode()]) name = [name stringByAppendingString:@" ✓"];
        [picker addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            if ([code isEqualToString:NWLanguageCode()]) return;
            // Recheck immediately before saving; a scan or block may have started.
            if (!NWCanRestartForLanguage() || NWBluetoothBusy()) { showMessage(self, NWText(@"language.busy")); return; }
            NSString *title = NWText(@"language.restartTitle"), *message = NWText(@"language.restartMessage");
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:NWText(@"language.apply") style:UIAlertActionStyleDefault handler:^(UIAlertAction *apply) {
                (void)apply;
                if (!NWCanRestartForLanguage() || NWBluetoothBusy()) { showMessage(self, NWText(@"language.busy")); return; }
                if (NWSetLanguage(code)) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ exit(0); });
            }]];
            // UIAlertAction dismisses the picker itself; wait for that transition.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                if (self.view.window && !self.presentedViewController) [self presentViewController:confirm animated:YES completion:nil];
            });
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:picker animated:YES completion:nil];
}
@end

static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);
static void (*originalViewWillAppear)(UIViewController *, SEL, BOOL);
static char baseInsetKey, bulkBoundKey;
static char infoOverlayKey, hotspotOverlayKey, refreshItemKey, themedBarKey, themedTabKey, browserItemKey;
static __weak UITabBarController *activeTab;
static const NSInteger refreshTag = 90730;
static BOOL installingUI, layingOut;
static void updateWiFi(void);
static void applyAppearance(void);
@interface NWActions : NSObject
- (void)refresh:(id)sender;
- (void)bulk:(id)sender;
- (void)changed:(NSNotification *)notification;
- (void)browse:(id)sender;
- (void)appearanceChanged:(NSNotification *)notification;
- (void)tabReselected:(NSNotification *)notification;
@end
@implementation NWActions
- (void)refresh:(id)sender {
    BOOL started = NWRefreshScan(); updateWiFi();
    if (!started && !NWScanBusy() && !NWBulkBusy()) showMessage(activeTab.selectedViewController, NWText(@"scan.unavailable"));
    if ([sender isKindOfClass:UIRefreshControl.class] && !NWScanBusy()) [(UIRefreshControl *)sender endRefreshing];
}
- (void)bulk:(id)sender { (void)sender; NWConfirmBulk(activeTab.selectedViewController); updateWiFi(); }
- (void)changed:(NSNotification *)notification { (void)notification; updateWiFi(); }
- (void)browse:(id)sender { (void)sender; NWPresentDeviceBrowser(activeTab.selectedViewController); }
- (void)appearanceChanged:(NSNotification *)notification { (void)notification; applyAppearance(); }
- (void)tabReselected:(NSNotification *)notification {
    UITabBarController *tab = notification.object;
    if ([notification.userInfo[@"tag"] integerValue] != 2 || tab.selectedIndex != 2 ||
        NWBluetoothTabSelected(tab) || NWBluetoothBusy()) return;
    UINavigationController *info = objc_getAssociatedObject(tab.selectedViewController, &infoOverlayKey);
    if (info.presentedViewController) return;
    [info popToRootViewControllerAnimated:NO];
}
@end
static NWActions *actions;
static void (*originalNavigationTitle)(UINavigationItem *, SEL, NSString *);
static NSString *displayAppTitle(NSString *title) {
    if (!title) return nil;
    for (NSString *old in @[@NWLegacyTitleShort, @NWLegacyTitleSpaced, @NWLegacyTitleHyphenated, @NWLegacyExecutable, @"NukeWireless"])
        if ([title caseInsensitiveCompare:old] == NSOrderedSame) return NW_BUILD_NAME;
    return title;
}
static void navigationTitle(UINavigationItem *item, SEL sel, NSString *title) {
    originalNavigationTitle(item, sel, NWNativeText(displayAppTitle(title)));
}
static void normalizeNavigationTitles(UIView *view) {
    if ([view isKindOfClass:UINavigationBar.class]) {
        for (UINavigationItem *item in ((UINavigationBar *)view).items) {
            NSString *title = NWNativeText(displayAppTitle(item.title));
            if (![title isEqualToString:item.title] && title) item.title = title;
        }
    }
    for (UIView *child in view.subviews) normalizeNavigationTitles(child);
}
static UITabBarController *tabForController(UIViewController *controller) {
    if ([controller isKindOfClass:UITabBarController.class]) return (UITabBarController *)controller;
    return controller.tabBarController;
}
static void prepareInfoTab(UITabBarController *tab) {
    if (!tab || installingUI || NWBluetoothTabSelected(tab) || tab.selectedIndex != 2 || !tab.selectedViewController) return;
    UIViewController *host = tab.selectedViewController;
    installingUI = YES;
    UINavigationController *info = objc_getAssociatedObject(host, &infoOverlayKey);
    if (!info) {
        info = [[UINavigationController alloc] initWithRootViewController:[NWInfoController new]];
        NWStyleNavigationBar(info.navigationBar);
        // SwiftUI owns the tab hosts and force-casts them during selection.
        // Keep the host identity and attach opaque content before its appearance.
        [host addChildViewController:info];
        info.view.backgroundColor = NWCanvasColor();
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
    for (UIView *child in host.view.subviews) if (child != info.view) child.hidden = YES;
    [host.view bringSubviewToFront:info.view];
    host.tabBarItem.title = NWText(@"info.title");
    installingUI = NO;
}
static UIScrollView *largestScroll(UIView *view) {
    UIScrollView *best = [view isKindOfClass:UIScrollView.class] ? (UIScrollView *)view : nil;
    for (UIView *child in view.subviews) {
        UIScrollView *candidate = largestScroll(child);
        if (candidate.bounds.size.width * candidate.bounds.size.height > best.bounds.size.width * best.bounds.size.height) best = candidate;
    }
    return best;
}
static void prepareHotspotTab(UITabBarController *tab) {
    if (!tab || installingUI || NWBluetoothTabSelected(tab) || tab.selectedIndex != 1) return;
    UIViewController *host = tab.selectedViewController;
    if (!host) return;
    installingUI = YES;
    UINavigationController *navigation = objc_getAssociatedObject(host, &hotspotOverlayKey);
    if (!navigation) {
        navigation = [[UINavigationController alloc] initWithRootViewController:NWHotspotController()];
        [host addChildViewController:navigation]; navigation.view.translatesAutoresizingMaskIntoConstraints = NO;
        [host.view addSubview:navigation.view];
        [NSLayoutConstraint activateConstraints:@[
            [navigation.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
            [navigation.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
            [navigation.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
            [navigation.view.trailingAnchor constraintEqualToAnchor:host.view.trailingAnchor]
        ]];
        [navigation didMoveToParentViewController:host];
        objc_setAssociatedObject(host, &hotspotOverlayKey, navigation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *view in host.view.subviews) if (view != navigation.view) view.hidden = YES;
    [host.view bringSubviewToFront:navigation.view]; installingUI = NO;
}
static void bindButton(UIButton *button, SEL action) {
    [button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:actions action:action forControlEvents:UIControlEventTouchUpInside];
}
static UINavigationBar *wifiNavigationBar(UIView *view) {
    if ([view isKindOfClass:UINavigationBar.class] &&
        [((UINavigationBar *)view).topItem.title isEqualToString:NW_BUILD_NAME])
        return (UINavigationBar *)view;
    for (UIView *child in view.subviews) {
        UINavigationBar *bar = wifiNavigationBar(child);
        if (bar) return bar;
    }
    return nil;
}
static void updateRefreshItem(UIView *root) {
    UINavigationBar *bar = wifiNavigationBar(root);
    UINavigationItem *item = bar.topItem;
    if (!item) return;
    // UIKit positions the icon alongside either a large or a collapsed title.
    UIBarButtonItem *refresh = objc_getAssociatedObject(item, &refreshItemKey);
    if (!refresh) {
        refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
            style:UIBarButtonItemStylePlain target:actions action:@selector(refresh:)];
        objc_setAssociatedObject(item, &refreshItemKey, refresh, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![item.rightBarButtonItems containsObject:refresh]) {
        NSMutableArray *items = [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray new];
        [items insertObject:refresh atIndex:0]; item.rightBarButtonItems = items;
    }
    UIBarButtonItem *browser = objc_getAssociatedObject(item, &browserItemKey);
    if (!browser) {
        browser = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
            style:UIBarButtonItemStylePlain target:actions action:@selector(browse:)];
        objc_setAssociatedObject(item, &browserItemKey, browser, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![item.rightBarButtonItems containsObject:browser]) {
        NSMutableArray *items = [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray new];
        [items addObject:browser]; item.rightBarButtonItems = items;
    }
    browser.accessibilityLabel = NWText(@"browser.title"); browser.tintColor = NWAccentColor();
    refresh.enabled = !NWScanBusy() && !NWBulkBusy();
    refresh.accessibilityLabel = NWText(NWScanBusy() ? @"scan.scanning" : @"refresh");
    refresh.tintColor = NWAccentColor();
    if (!objc_getAssociatedObject(bar, &themedBarKey)) {
        NWStyleNavigationBar(bar);
        objc_setAssociatedObject(bar, &themedBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [[root viewWithTag:refreshTag] removeFromSuperview];
}
static void updateWiFi(void) {
    UITabBarController *tab = activeTab;
    if (layingOut || !tab.isViewLoaded || NWBluetoothTabSelected(tab) || tab.selectedIndex != 0) return;
    layingOut = YES;
    UIView *root = tab.selectedViewController.view;
    normalizeNavigationTitles(root);
    updateRefreshItem(root);
    styleWiFiLists(root);
    UIView *bulkPanel = [tab.view viewWithTag:90122];
    UIButton *bulkButton = [bulkPanel isKindOfClass:UIButton.class] ? (UIButton *)bulkPanel : nil;
    if (!bulkButton) {
        for (UIView *child in bulkPanel.subviews) {
            if ([child isKindOfClass:UIButton.class] &&
                (!bulkButton || child.bounds.size.width > bulkButton.bounds.size.width))
                bulkButton = (UIButton *)child;
        }
    }
    if (bulkButton && !bulkPanel.hidden && !bulkButton.hidden) {
        if (bulkPanel != bulkButton) {
            bulkPanel.backgroundColor = NWPanelColor(); bulkPanel.layer.cornerRadius = 18;
            bulkPanel.layer.borderWidth = 0.7;
            bulkPanel.layer.borderColor = [NWAccentColor() colorWithAlphaComponent:0.3].CGColor;
        }
        bulkButton.layer.cornerRadius = 12;
        for (UIView *child in bulkPanel.subviews) {
            if ([child isKindOfClass:UILabel.class]) {
                NSString *summary = [NSString stringWithFormat:@"%@\n%@", NWScanSummary(), NWText(@"scan.pullHint")];
                if (![((UILabel *)child).text isEqualToString:summary]) ((UILabel *)child).text = summary;
            } else if ([child isKindOfClass:UIButton.class] && child != bulkButton) {
                UIButton *names = (UIButton *)child;
                names.layer.cornerRadius = 12; names.layer.borderWidth = 0.7;
                names.layer.borderColor = [NWAccentColor() colorWithAlphaComponent:0.35].CGColor;
                if (![names.currentTitle isEqualToString:NWText(@"device.names")]) [names setTitle:NWText(@"device.names") forState:UIControlStateNormal];
            }
        }
        if (bulkPanel == bulkButton) {
            CGRect bar = [tab.tabBar convertRect:tab.tabBar.bounds toView:tab.view];
            CGFloat width = MIN(186, MAX(0, tab.view.bounds.size.width - 24));
            CGRect position = CGRectMake((tab.view.bounds.size.width - width) / 2,
                                         CGRectGetMinY(bar) - 58, width, 42);
            if (!CGRectEqualToRect(bulkButton.frame, position)) bulkButton.frame = position;
        }
        if (!objc_getAssociatedObject(bulkButton, &bulkBoundKey)) {
            bindButton(bulkButton, @selector(bulk:));
            objc_setAssociatedObject(bulkButton, &bulkBoundKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSString *bulkTitle = NWBulkTitle();
        if (![bulkButton.currentTitle isEqualToString:bulkTitle]) [bulkButton setTitle:bulkTitle forState:UIControlStateNormal];
        BOOL bulkEnabled = !NWBulkBusy();
        if (bulkButton.enabled != bulkEnabled) bulkButton.enabled = bulkEnabled;
    }
    UIScrollView *scroll = largestScroll(root);
    if (scroll) {
        if (!scroll.refreshControl) scroll.refreshControl = [UIRefreshControl new];
        UIRefreshControl *control = scroll.refreshControl;
        [control removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
        [control addTarget:actions action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
        if (!NWScanBusy()) [control endRefreshing];
        if (bulkButton && !bulkPanel.hidden && !bulkButton.hidden) {
            NSNumber *base = objc_getAssociatedObject(scroll,&baseInsetKey);
            if (!base) { base = @(scroll.contentInset.bottom); objc_setAssociatedObject(scroll,&baseInsetKey,base,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            CGRect scrollFrame = [scroll convertRect:scroll.bounds toView:root];
            CGRect panelFrame = [bulkPanel convertRect:bulkPanel.bounds toView:root];
            CGFloat systemInset = scroll.adjustedContentInset.bottom - scroll.contentInset.bottom;
            CGFloat bottom = MAX(base.doubleValue, CGRectGetMaxY(scrollFrame)-CGRectGetMinY(panelFrame)-systemInset+16);
            UIEdgeInsets inset = scroll.contentInset; inset.bottom = bottom;
            if (!UIEdgeInsetsEqualToEdgeInsets(inset,scroll.contentInset)) scroll.contentInset = inset;
            UIEdgeInsets indicator = scroll.verticalScrollIndicatorInsets; indicator.bottom = bottom;
            if (!UIEdgeInsetsEqualToEdgeInsets(indicator,scroll.verticalScrollIndicatorInsets))
                scroll.verticalScrollIndicatorInsets = indicator;
        }
    }
    layingOut = NO;
}
static void installUI(UIViewController *controller) {
    UITabBarController *tab = tabForController(controller);
    if (!tab || installingUI) return;
    NWPrepareMainTabs(tab); prepareInfoTab(tab); prepareHotspotTab(tab);
    activeTab = tab; installingUI = YES;
    if (!objc_getAssociatedObject(tab.tabBar, &themedTabKey)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithDefaultBackground];
        appearance.backgroundColor = NWCanvasColor();
        appearance.shadowColor = [NWAccentColor() colorWithAlphaComponent:0.18];
        tab.tabBar.standardAppearance = appearance; tab.tabBar.scrollEdgeAppearance = appearance;
        tab.tabBar.tintColor = NWAccentColor();
        objc_setAssociatedObject(tab.tabBar, &themedTabKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    installingUI = NO;
    updateWiFi();
}
static void applyAppearance(void) {
    UITabBarController *tab = activeTab;
    if (!tab.isViewLoaded) return;
    tab.view.tintColor = NWAccentColor();
    objc_setAssociatedObject(tab.tabBar, &themedTabKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationBar *wifiBar = wifiNavigationBar(tab.viewControllers.firstObject.view);
    if (wifiBar) {
        NWStyleNavigationBar(wifiBar);
        objc_setAssociatedObject(wifiBar, &themedBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIViewController *host in tab.viewControllers) {
        UINavigationController *info = objc_getAssociatedObject(host, &infoOverlayKey);
        if (!info) continue;
        NWStyleNavigationBar(info.navigationBar);
        info.view.backgroundColor = NWCanvasColor();
        for (UIViewController *controller in info.viewControllers) {
            if (!controller.isViewLoaded || ![controller isKindOfClass:UITableViewController.class]) continue;
            UITableView *table = ((UITableViewController *)controller).tableView;
            table.backgroundColor = NWCanvasColor(); table.tintColor = NWAccentColor();
            CGPoint position = table.contentOffset;
            [UIView performWithoutAnimation:^{ [table reloadData]; [table layoutIfNeeded]; table.contentOffset = position; }];
        }
    }
    NWStyleMainTabs(tab); installUI(tab);
}
static void appeared(UIViewController *controller, SEL sel, BOOL animated) {
    originalViewDidAppear(controller,sel,animated);
    dispatch_async(dispatch_get_main_queue(), ^{ installUI(controller); });
}
static void willAppear(UIViewController *controller, SEL sel, BOOL animated) {
    prepareInfoTab(tabForController(controller));
    originalViewWillAppear(controller, sel, animated);
    prepareInfoTab(tabForController(controller));
    prepareHotspotTab(tabForController(controller));
}
__attribute__((constructor)) static void installExtension(void) {
    syslog(LOG_NOTICE, "NukeWireless: diagnostic9 embedded UI loaded");
    // Both are mandatory app dependencies. Initialize our adapter exactly once
    // before wrapping its methods, regardless of dyld constructor order.
    void (*initializeAdapter)(void) = dlsym(RTLD_DEFAULT, "NWBootstrapInitialize");
    if (initializeAdapter) initializeAdapter();
    NWInstallLanguageHooks();
    NWInstallDeviceActionPresentation();
    NWDiagnosticsInstall();
    NWInstallScanHooks();
    dispatch_async(dispatch_get_main_queue(), ^{
        actions = [NWActions new];
        [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(tabReselected:) name:NWMainTabReselected object:nil];
        [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(changed:) name:NWStateChanged object:nil];
        [NSNotificationCenter.defaultCenter addObserver:actions selector:@selector(appearanceChanged:) name:NWAppearanceChanged object:nil];
        Method method = class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
        originalViewDidAppear = (void *)method_setImplementation(method,(IMP)appeared);
        method = class_getInstanceMethod(UIViewController.class,@selector(viewWillAppear:));
        originalViewWillAppear = (void *)method_setImplementation(method,(IMP)willAppear);
        method = class_getInstanceMethod(UINavigationItem.class,@selector(setTitle:));
        originalNavigationTitle = (void *)method_setImplementation(method,(IMP)navigationTitle);
        NWInstallPacketIntervalHook();
        // Reconcile actions from the unchanged individual Swift controls too.
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            if (activeTab.selectedIndex == 0 && !NWBluetoothTabSelected(activeTab) && activeTab.view.window) {
                NWMaintainWiFiScan(); NWReconcileDeviceStates(); updateWiFi(); NWRefreshVisibleDeviceBrowser();
            }
        }];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                installUI(window.rootViewController);
            }
        }
    });
}

#ifdef NW_UI_TESTING
// Only linked into the SwiftUI simulator fixture, never the device package.
void NWUIRegressionSetLanguage(int spanish) { NWSetLanguage(spanish ? @"es" : @"en"); }
int NWUIRegressionPrepareResume(int tag) { return NWMainTabsResumePrepare(activeTab, tag); }
int NWUIRegressionCheckResume(void) { return NWMainTabsResumeCheck(activeTab); }
int NWUIRegressionDiagnosticNavigation(int phase) {
    static UINavigationController *navigation;
    static UIViewController *diagnostics;
    static NSArray *hosts;
    static id<UITabBarControllerDelegate> delegate;
    UITabBarController *tab = activeTab;
    if (!tab || tab.viewControllers.count != 3) return 80;
    if (phase == 0) {
        hosts = [tab.viewControllers copy]; delegate = tab.delegate;
        NWMainTabsUIRegressionSelect(tab, 2); return 0;
    }
    if (![hosts isEqual:tab.viewControllers] || delegate != tab.delegate || tab.selectedIndex != 2) return 81;
    navigation = objc_getAssociatedObject(tab.selectedViewController, &infoOverlayKey);
    if (!navigation || !navigation.view.window) return 82;
    if (phase == 1) {
        NWInfoController *info = (NWInfoController *)navigation.topViewController;
        if (![info isKindOfClass:NWInfoController.class]) return 83;
        [info tableView:info.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:1]];
        diagnostics = navigation.topViewController;
    } else if (phase == 2 || phase == 4) {
        if (navigation.topViewController != diagnostics || ![diagnostics.title isEqual:NWText(@"diag.title")]) return 84;
        UITableViewController *table = (UITableViewController *)diagnostics;
        [table tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:4 inSection:1]];
        if (navigation.topViewController == diagnostics) return 85;
    } else if (phase == 3) {
        UIViewController *menu = navigation.topViewController;
        if (![menu.title isEqual:NWText(@"bt.title")] || menu.navigationItem.leftBarButtonItem ||
            menu.navigationItem.hidesBackButton || navigation.navigationBar.backItem != diagnostics.navigationItem ||
            ![menu.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.bluetooth.help"]) return 86;
        @try {
            NWBluetoothUIRegressionCatalogState(1);
            NWMainTabsUIRegressionSelect(tab, 2);
            if (navigation.topViewController != menu) return 87;
            if (!menu.navigationItem.hidesBackButton) return 93;
            if (navigation.interactivePopGestureRecognizer.enabled) return 94;
            if (![menu.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.bluetooth.stop"]) return 95;
            NWBluetoothUIRegressionCatalogState(2);
            if (menu.navigationItem.rightBarButtonItem.enabled) return 88;
        } @finally { NWBluetoothUIRegressionCatalogState(0); }
        if (menu.navigationItem.hidesBackButton || !navigation.interactivePopGestureRecognizer.enabled ||
            ![menu.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.bluetooth.help"]) return 89;
        [navigation popViewControllerAnimated:NO];
        if (navigation.topViewController != diagnostics) return 90;
    } else if (phase == 5) {
        NWMainTabsUIRegressionSelect(tab, 2);
        if (navigation.viewControllers.count != 1 || ![navigation.topViewController isKindOfClass:NWInfoController.class]) return 91;
    } else if (phase == 6) {
        NWMainTabsUIRegressionSelect(tab, 0);
        if (tab.selectedIndex != 0 || NWBluetoothTabSelected(tab)) return 92;
    }
    return 0;
}
int NWUIRegressionCheck(int phase) {
    static NSArray<UIViewController *> *hosts;
    UITabBarController *tab = activeTab;
    if (!tab || tab.viewControllers.count != 3) return 1;
    if (phase == 0) {
        extern int NWEmbeddedStartupUIRegression(void);
        if (NWEmbeddedStartupUIRegression() || ![NSBundle.mainBundle.infoDictionary[@"NukeWirelessUIIntegration"] isEqual:@"embedded-required-v1"]) return 19;
        unsigned copies = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
            NSString *path = [NSString stringWithUTF8String:_dyld_get_image_name(i) ?: ""];
            if ([path.lastPathComponent isEqual:@"NukeWirelessInfo.dylib"]) ++copies;
        }
        if (copies != 1) return 20;
        hosts = [tab.viewControllers copy];
        UINavigationItem *item = [UINavigationItem new];
        item.title = @NWLegacyTitleShort;
        if (![item.title isEqualToString:NW_BUILD_NAME]) return 2;
        item.title = @"Current network";
        if (![item.title isEqualToString:@"Current network"]) return 3;
        BOOL spanish = [NWLanguageCode() isEqualToString:@"es"];
        NSString *expected = spanish ? @"Bloquear equipo" : @"Block device";
        if (![[NSBundle.mainBundle localizedStringForKey:@"Block Device" value:nil table:nil] isEqualToString:expected]) return 12;
        UIAlertAction *action = [UIAlertAction actionWithTitle:@"Block Device" style:UIAlertActionStyleDefault handler:nil];
        if (![action.title isEqualToString:expected]) return 13;
        UITextField *field = [UITextField new]; field.placeholder = @"Enter new name";
        if (![field.placeholder isEqualToString:(spanish ? @"Introduce un nombre nuevo" : @"Enter a new name")]) return 14;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:@"Nombres" forState:UIControlStateNormal];
        if (![button.currentTitle isEqualToString:(spanish ? @"Nombres" : @"Names")]) return 15;
        if (![NWNativeText(@"192.168.1.1") isEqualToString:@"192.168.1.1"]) return 16;
        return 0;
    }
    for (NSUInteger i = 0; i < hosts.count; i++) if (hosts[i] != tab.viewControllers[i]) return 4;
    if (phase == 1) {
        if (tab.selectedIndex != 2) return 5;
        UIViewController *host = tab.selectedViewController;
        UINavigationController *info = objc_getAssociatedObject(host, &infoOverlayKey);
        if (!info || info.parentViewController != host || !info.view.window) return 6;
        if (![info.topViewController isKindOfClass:NWInfoController.class]) return 7;
        NWInfoController *content = (NWInfoController *)info.topViewController;
        if ([content tableView:content.tableView numberOfRowsInSection:1] != 6) return 8;
        UITableViewCell *diagnostics = [content tableView:content.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:5 inSection:1]];
        if (![diagnostics.accessibilityIdentifier isEqual:@"nw.info.diagnostics"]) return 18;
        for (UIView *child in host.view.subviews) if (child != info.view && !child.hidden) return 9;
        [host.view layoutIfNeeded];
        if (!CGSizeEqualToSize(info.view.bounds.size, host.view.bounds.size)) return 10;
        UITableViewCell *language = [content tableView:content.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:1]];
        UIListContentConfiguration *config = (UIListContentConfiguration *)language.contentConfiguration;
        if (![config.text isEqualToString:NWText(@"language.title")]) return 17;
    } else if (phase == 2 && tab.selectedIndex != 0) return 11;
    else if (phase == 3 || phase == 4) return NWMainTabsRegressionCheck(tab, phase == 3);
    else if (phase == 5) return NWMainTabsStabilityCheck(tab);
    return 0;
}
#endif
