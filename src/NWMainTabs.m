#import "NWMainTabs.h"
#import "NWBuild.h"
#import "NWBluetooth.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import <objc/runtime.h>
#include <math.h>

// SwiftUI force-casts its three original hosts during selection. Keep those
// hosts and its delegate intact; a presentation bar routes native selections
// and a navigation stack contained in the Wi-Fi host provides Bluetooth.
// Adding it directly to UITabBarController also appends it to SwiftUI's array.
@interface NWMainTabs : NSObject <UITabBarDelegate>
@property(nonatomic, weak) UITabBarController *owner;
@property(nonatomic, strong) UITabBar *bar;
@property(nonatomic, strong) UINavigationController *bluetooth;
@property(nonatomic) BOOL bluetoothSelected;
@property(nonatomic) NSUInteger foregroundRestorations;
- (void)selectTag:(NSInteger)tag;
- (void)style;
- (void)restoreBar;
@end
static char mainTabsKey;
@implementation NWMainTabs
- (instancetype)init {
    self = [super init];
    if (self) {
        for (NSString *name in @[UIApplicationWillEnterForegroundNotification, UIApplicationDidBecomeActiveNotification,
            UISceneWillEnterForegroundNotification, UISceneDidActivateNotification])
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:name object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)restoreBar {
    UITabBarController *tab = self.owner;
    if (!tab.isViewLoaded || !self.bar) return;
    // Keep the native bar for SwiftUI's layout and selection binding. Its
    // controls are covered by a sibling, so rebuilding its children cannot
    // paint over our four items or receive their touches/accessibility focus.
    tab.tabBar.userInteractionEnabled = NO;
    tab.tabBar.accessibilityElements = nil;
    tab.tabBar.accessibilityElementsHidden = YES;
    self.bar.layer.zPosition = MAX(1, tab.tabBar.layer.zPosition + 1);
    [tab.view bringSubviewToFront:tab.tabBar];
    [tab.view bringSubviewToFront:self.bar];
}
- (void)foreground:(NSNotification *)notification {
    UITabBarController *tab = self.owner;
    if (!tab.isViewLoaded) return;
    if ([notification.object isKindOfClass:UIScene.class] && tab.view.window.windowScene != notification.object) return;
    self.foregroundRestorations++;
    NWPrepareMainTabs(tab); [self style];
    // UIKit/SwiftUI can finish reconstructing their bar after activation.
    // Reconcile once more on the next main turn without changing selection.
    __weak NWMainTabs *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NWMainTabs *tabs = weakSelf;
        if (tabs.owner.isViewLoaded && tabs.owner.view.window) NWPrepareMainTabs(tabs.owner);
    });
}
- (void)style {
    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithOpaqueBackground]; appearance.backgroundColor = NWCanvasColor();
    appearance.shadowColor = [NWAccentColor() colorWithAlphaComponent:0.18];
    UIColor *normal = [UIColor.secondaryLabelColor resolvedColorWithTraitCollection:self.bar.traitCollection];
    UIColor *selected = [NWAccentColor() resolvedColorWithTraitCollection:self.bar.traitCollection];
    for (UITabBarItemAppearance *item in @[appearance.stackedLayoutAppearance,
        appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance]) {
        item.normal.iconColor = normal; item.normal.titleTextAttributes = @{NSForegroundColorAttributeName:normal};
        item.selected.iconColor = selected; item.selected.titleTextAttributes = @{NSForegroundColorAttributeName:selected};
    }
    self.bar.standardAppearance = appearance; self.bar.scrollEdgeAppearance = appearance;
    self.bar.tintColor = NWAccentColor(); self.bar.backgroundColor = NWCanvasColor();
    self.bar.items[0].title = NWText(@"tabs.wifi");
    self.bar.items[1].title = NWText(@"tabs.hotspot");
    self.bar.items[2].title = NWText(@"bt.title");
    self.bar.items[3].title = NWText(@"info.title");
    if (self.bluetooth) {
        NWStyleNavigationBar(self.bluetooth.navigationBar);
        self.bluetooth.view.backgroundColor = NWCanvasColor();
    }
}
- (void)selectTag:(NSInteger)tag {
    UITabBarController *tab = self.owner;
    if (!tab || tag < 0 || tag > 3) return;
    BOOL wantsBluetooth = tag == 3;
    NSUInteger nativeIndex = wantsBluetooth ? 0 : (NSUInteger)tag;
    UIViewController *nativeHost = tab.viewControllers[nativeIndex];
    id<UITabBarControllerDelegate> delegate = tab.delegate;
    if ([delegate respondsToSelector:@selector(tabBarController:shouldSelectViewController:)] &&
        ![delegate tabBarController:tab shouldSelectViewController:nativeHost]) {
        NSInteger oldTag = self.bluetoothSelected ? 3 : (NSInteger)tab.selectedIndex;
        for (UITabBarItem *item in self.bar.items) if (item.tag == oldTag) self.bar.selectedItem = item;
        return;
    }
    BOOL wasBluetooth = self.bluetoothSelected;
    self.bluetoothSelected = wantsBluetooth;
    if (wantsBluetooth) tab.selectedIndex = 0;
    if (wantsBluetooth && !self.bluetooth) {
        UIViewController *host = tab.viewControllers.firstObject;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:NWBluetoothController()];
        self.bluetooth = nav;
        [host addChildViewController:nav];
        nav.view.hidden = YES; nav.view.translatesAutoresizingMaskIntoConstraints = NO;
        nav.view.backgroundColor = NWCanvasColor(); [host.view addSubview:nav.view];
        [NSLayoutConstraint activateConstraints:@[
            [nav.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
            [nav.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
            [nav.view.trailingAnchor constraintEqualToAnchor:host.view.trailingAnchor],
            // The native selection may not have attached the host to tab.view
            // yet. Keep constraints inside the host's hierarchy.
            [nav.view.bottomAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.bottomAnchor]
        ]];
        [nav didMoveToParentViewController:host]; [self style];
    }
    if (wantsBluetooth != wasBluetooth) {
        self.bluetooth.view.hidden = !wantsBluetooth;
        [self.bluetooth beginAppearanceTransition:wantsBluetooth animated:NO];
        [self.bluetooth endAppearanceTransition];
    }
    if (wantsBluetooth) {
        [self.bluetooth.view.superview bringSubviewToFront:self.bluetooth.view];
        [tab.view viewWithTag:90122].hidden = YES;
    } else {
        // The pinned legacy appearance hook shows this panel only at index 0.
        // Restore that policy even if Bluetooth was entered from Info/Hotspot,
        // or the panel was created after the asynchronous native selection.
        [tab.view viewWithTag:90122].hidden = tag != 0;
        tab.selectedIndex = (NSUInteger)tag;
    }
    for (UITabBarItem *item in self.bar.items) if (item.tag == tag) self.bar.selectedItem = item;
    // Keep SwiftUI's selection binding aligned with UIKit. Only the three
    // original hosts ever reach its delegate, including Bluetooth's underlay.
    if ([delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])
        [delegate tabBarController:tab didSelectViewController:nativeHost];
    [self restoreBar];
}
- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    (void)tabBar; [self selectTag:item.tag];
}
@end
BOOL NWBluetoothTabSelected(UITabBarController *tab) {
    return [(NWMainTabs *)objc_getAssociatedObject(tab, &mainTabsKey) bluetoothSelected];
}
void NWPrepareMainTabs(UITabBarController *tab) {
    if (!tab || tab.viewControllers.count != 3) return;
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs) {
        tabs = [NWMainTabs new]; tabs.owner = tab;
        objc_setAssociatedObject(tab, &mainTabsKey, tabs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITabBar *bar = [UITabBar new]; tabs.bar = bar; bar.delegate = tabs;
        bar.accessibilityIdentifier = @"nw.main.tabs";
        NSArray *titles = @[NWText(@"tabs.wifi"), NWText(@"tabs.hotspot"), NWText(@"bt.title"), NWText(@"info.title")];
        NSArray *symbols = @[@"wifi", @"link", @"antenna.radiowaves.left.and.right", @"info.circle"];
        NSArray *tags = @[@0, @1, @3, @2]; NSMutableArray *items = [NSMutableArray new];
        for (NSUInteger i=0; i<4; i++) {
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:titles[i] image:[UIImage systemImageNamed:symbols[i]] tag:[tags[i] integerValue]];
            item.accessibilityIdentifier = [NSString stringWithFormat:@"nw.tab.%@", tags[i]]; [items addObject:item];
        }
        bar.items = items; bar.itemPositioning = UITabBarItemPositioningFill;
        bar.translatesAutoresizingMaskIntoConstraints = NO; [tab.view addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [bar.topAnchor constraintEqualToAnchor:tab.tabBar.topAnchor],
            [bar.bottomAnchor constraintEqualToAnchor:tab.tabBar.bottomAnchor],
            [bar.leadingAnchor constraintEqualToAnchor:tab.tabBar.leadingAnchor],
            [bar.trailingAnchor constraintEqualToAnchor:tab.tabBar.trailingAnchor]
        ]];
        [tabs style];
    }
    if (!tabs.bluetoothSelected) {
        for (UITabBarItem *item in tabs.bar.items) if (item.tag == (NSInteger)tab.selectedIndex) tabs.bar.selectedItem = item;
    } else {
        [tabs.bluetooth.view.superview bringSubviewToFront:tabs.bluetooth.view];
        [tab.view viewWithTag:90122].hidden = YES;
    }
    [tabs restoreBar];
}
void NWStyleMainTabs(UITabBarController *tab) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    [tabs style]; [tabs restoreBar];
}
#ifdef NW_UI_TESTING
int NWMainTabsRegressionCheck(UITabBarController *tab, BOOL selectBluetooth) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs || tabs.bar.items.count != 4 || tabs.bar.superview != tab.view) return 20;
    if (selectBluetooth) {
        if (![tab.view viewWithTag:90122]) {
            UIView *panel = [UIView new]; panel.tag = 90122;
            panel.hidden = tab.selectedIndex != 0; [tab.view addSubview:panel];
        }
        [tabs selectTag:3]; [tab.view layoutIfNeeded];
        // UIKit attaches the newly selected host at the next transition. The
        // delayed stability check verifies window attachment and geometry.
        if (!tabs.bluetoothSelected || tabs.bar.selectedItem.tag != 3 || tabs.bluetooth.view.hidden ||
            ![tab.view viewWithTag:90122].hidden) return 21;
        if (tab.viewControllers.count != 3 || tabs.bluetooth.parentViewController != tab.viewControllers.firstObject ||
            tabs.bluetooth.viewControllers.count != 1) return 22;
    } else {
        [tabs selectTag:1]; [tabs selectTag:2];
        [tabs selectTag:0];
        if (tabs.bluetoothSelected || tabs.bar.selectedItem.tag != 0 || !tabs.bluetooth.view.hidden || tab.selectedIndex != 0 ||
            [tab.view viewWithTag:90122].hidden) return 24;
    }
    return 0;
}
int NWMainTabsStabilityCheck(UITabBarController *tab) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs.bluetoothSelected || tab.selectedIndex != 0 || tab.viewControllers.count != 3 ||
        !tabs.bluetooth.view.window || tabs.bluetooth.view.hidden || tabs.bar.selectedItem.tag != 3 ||
        ![tab.view viewWithTag:90122].hidden) return 25;
    if (![tabs.bluetooth.topViewController.title isEqual:NWText(@"bt.title")]) return 26;
    CGRect frame = [tabs.bluetooth.view.superview convertRect:tabs.bluetooth.view.frame toView:tab.view];
    return CGRectGetMaxY(frame) > CGRectGetMinY(tab.tabBar.frame) + 1 ? 23 : 0;
}
static NSInteger resumeTag;
static NSUInteger resumeRestorations;
static NSArray<UIViewController *> *resumeHosts;
static id<UITabBarControllerDelegate> resumeDelegate;
static UIViewController *resumeTop;
static UIView *resumeNativeContent;
static UINavigationBar *resumeWiFiBar(UIView *view) {
    if ([view isKindOfClass:UINavigationBar.class] &&
        [((UINavigationBar *)view).topItem.title isEqualToString:NW_BUILD_NAME]) return (UINavigationBar *)view;
    for (UIView *child in view.subviews) {
        UINavigationBar *bar = resumeWiFiBar(child);
        if (bar) return bar;
    }
    return nil;
}
int NWMainTabsResumePrepare(UITabBarController *tab, NSInteger tag) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs || tag < 0 || tag > 3) return 30;
    [resumeNativeContent removeFromSuperview];
    [tabs selectTag:tag];
    if (tag == 3 && tabs.bluetooth.viewControllers.count == 1) {
        UITableViewController *menu = (UITableViewController *)tabs.bluetooth.topViewController;
        [menu tableView:menu.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    }
    [tab.view layoutIfNeeded];
    resumeTag = tag; resumeRestorations = tabs.foregroundRestorations;
    resumeHosts = [tab.viewControllers copy]; resumeDelegate = tab.delegate;
    resumeTop = tag == 3 ? tabs.bluetooth.topViewController : nil;
    // Model native controls being restored/reordered. Do not inspect or hook
    // UIKit's private view classes. A real process background/return follows.
    resumeNativeContent = [[UIView alloc] initWithFrame:tab.tabBar.bounds];
    resumeNativeContent.backgroundColor = UIColor.systemRedColor;
    [tab.tabBar addSubview:resumeNativeContent];
    for (UIView *child in [tab.tabBar.subviews copy]) [tab.tabBar bringSubviewToFront:child];
    [tab.view bringSubviewToFront:tab.tabBar];
    tab.tabBar.userInteractionEnabled = YES;
    tab.tabBar.accessibilityElementsHidden = NO;
    return 0;
}
int NWMainTabsResumeCheck(UITabBarController *tab) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs || tabs.foregroundRestorations <= resumeRestorations || tabs.bar.superview != tab.view ||
        tabs.bar.items.count != 4 || tabs.bar.selectedItem.tag != resumeTag ||
        tabs.bluetoothSelected != (resumeTag == 3) || tab.selectedIndex != (NSUInteger)(resumeTag == 3 ? 0 : resumeTag)) return 31;
    if (![resumeHosts isEqual:tab.viewControllers] || tab.delegate != resumeDelegate ||
        tab.tabBar.userInteractionEnabled || !tab.tabBar.accessibilityElementsHidden ||
        tabs.bar.accessibilityElementsHidden || !tabs.bar.userInteractionEnabled) return 32;
    if (tabs.bar.layer.zPosition <= tab.tabBar.layer.zPosition ||
        [tab.view.subviews indexOfObject:tabs.bar] <= [tab.view.subviews indexOfObject:tab.tabBar]) return 33;
    CGRect native = [tab.tabBar convertRect:tab.tabBar.bounds toView:tab.view];
    CGRect presentation = [tabs.bar convertRect:tabs.bar.bounds toView:tab.view];
    if (fabs(native.origin.x - presentation.origin.x) > 1 || fabs(native.origin.y - presentation.origin.y) > 1 ||
        fabs(native.size.width - presentation.size.width) > 1 || fabs(native.size.height - presentation.size.height) > 1) return 34;
    UIColor *background = [tabs.bar.standardAppearance.backgroundColor resolvedColorWithTraitCollection:tabs.bar.traitCollection];
    if (!background || CGColorGetAlpha(background.CGColor) < 1) return 35;
    if (resumeTag == 3 && (tabs.bluetooth.topViewController != resumeTop || tabs.bluetooth.view.hidden ||
        ![tab.view viewWithTag:90122].hidden)) return 36;
    if (resumeTag == 0) {
        UINavigationBar *bar = resumeWiFiBar(tab.selectedViewController.view);
        UIColor *expected = [UIColor.labelColor resolvedColorWithTraitCollection:bar.traitCollection];
        UIColor *title = [bar.standardAppearance.titleTextAttributes[NSForegroundColorAttributeName] resolvedColorWithTraitCollection:bar.traitCollection];
        UIColor *large = [bar.standardAppearance.largeTitleTextAttributes[NSForegroundColorAttributeName] resolvedColorWithTraitCollection:bar.traitCollection];
        if (!bar || ![title isEqual:expected] || ![large isEqual:expected]) return 37;
    }
    [resumeNativeContent removeFromSuperview]; resumeNativeContent = nil;
    return 0;
}
#endif
