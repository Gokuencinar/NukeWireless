#import "NWMainTabs.h"
#import "NWBluetooth.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import <objc/runtime.h>

// SwiftUI force-casts its three original hosts during selection. Keep those
// hosts and its delegate intact; a presentation bar routes native selections
// and a navigation stack contained in the Wi-Fi host provides Bluetooth.
// Adding it directly to UITabBarController also appends it to SwiftUI's array.
@interface NWMainTabs : NSObject <UITabBarDelegate>
@property(nonatomic, weak) UITabBarController *owner;
@property(nonatomic, strong) UITabBar *bar;
@property(nonatomic, strong) UINavigationController *bluetooth;
@property(nonatomic) BOOL bluetoothSelected;
@property(nonatomic, weak) UIView *suppressedPanel;
@property(nonatomic) BOOL panelWasHidden;
- (void)selectTag:(NSInteger)tag;
- (void)style;
@end
static char mainTabsKey;
@implementation NWMainTabs
- (void)style {
    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithOpaqueBackground]; appearance.backgroundColor = NWCanvasColor();
    appearance.shadowColor = [NWAccentColor() colorWithAlphaComponent:0.18];
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
        UIView *panel = [tab.view viewWithTag:90122];
        if (panel != self.suppressedPanel) { self.suppressedPanel = panel; self.panelWasHidden = panel.hidden; }
        panel.hidden = YES;
    } else {
        self.suppressedPanel.hidden = self.panelWasHidden; self.suppressedPanel = nil;
        tab.selectedIndex = (NSUInteger)tag;
    }
    for (UITabBarItem *item in self.bar.items) if (item.tag == tag) self.bar.selectedItem = item;
    [tab.view bringSubviewToFront:tab.tabBar];
    // Keep SwiftUI's selection binding aligned with UIKit. Only the three
    // original hosts ever reach its delegate, including Bluetooth's underlay.
    if ([delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])
        [delegate tabBarController:tab didSelectViewController:nativeHost];
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
        bar.translatesAutoresizingMaskIntoConstraints = NO; [tab.tabBar addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [bar.topAnchor constraintEqualToAnchor:tab.tabBar.topAnchor],
            [bar.bottomAnchor constraintEqualToAnchor:tab.tabBar.bottomAnchor],
            [bar.leadingAnchor constraintEqualToAnchor:tab.tabBar.leadingAnchor],
            [bar.trailingAnchor constraintEqualToAnchor:tab.tabBar.trailingAnchor]
        ]];
        // Expose exactly four items to VoiceOver, rather than both bars.
        tab.tabBar.accessibilityElements = @[bar]; [tabs style];
    }
    if (!tabs.bluetoothSelected) {
        for (UITabBarItem *item in tabs.bar.items) if (item.tag == (NSInteger)tab.selectedIndex) tabs.bar.selectedItem = item;
    } else {
        [tabs.bluetooth.view.superview bringSubviewToFront:tabs.bluetooth.view];
        [tab.view viewWithTag:90122].hidden = YES;
    }
    [tab.tabBar bringSubviewToFront:tabs.bar]; [tab.view bringSubviewToFront:tab.tabBar];
}
void NWStyleMainTabs(UITabBarController *tab) { [(NWMainTabs *)objc_getAssociatedObject(tab, &mainTabsKey) style]; }
#ifdef NW_UI_TESTING
int NWMainTabsRegressionCheck(UITabBarController *tab, BOOL selectBluetooth) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    if (!tabs || tabs.bar.items.count != 4 || tabs.bar.superview != tab.tabBar) return 20;
    if (selectBluetooth) {
        [tabs selectTag:3]; [tab.view layoutIfNeeded];
        if (!tabs.bluetoothSelected || tabs.bar.selectedItem.tag != 3 || !tabs.bluetooth.view.window || tabs.bluetooth.view.hidden) return 21;
        if (tab.viewControllers.count != 3 || tabs.bluetooth.parentViewController != tab.viewControllers.firstObject || tabs.bluetooth.viewControllers.count != 1 ||
            ![tabs.bluetooth.topViewController.title isEqual:NWText(@"bt.title")]) return 22;
        CGRect frame = [tabs.bluetooth.view.superview convertRect:tabs.bluetooth.view.frame toView:tab.view];
        if (CGRectGetMaxY(frame) > CGRectGetMinY(tab.tabBar.frame) + 1) return 23;
    } else {
        [tabs selectTag:1]; [tabs selectTag:2];
        [tabs selectTag:0];
        if (tabs.bluetoothSelected || tabs.bar.selectedItem.tag != 0 || !tabs.bluetooth.view.hidden || tab.selectedIndex != 0) return 24;
    }
    return 0;
}
int NWMainTabsStabilityCheck(UITabBarController *tab) {
    NWMainTabs *tabs = objc_getAssociatedObject(tab, &mainTabsKey);
    return tabs.bluetoothSelected && tab.selectedIndex == 0 && tab.viewControllers.count == 3 &&
        tabs.bluetooth.view.window && !tabs.bluetooth.view.hidden && tabs.bar.selectedItem.tag == 3 ? 0 : 25;
}
#endif
