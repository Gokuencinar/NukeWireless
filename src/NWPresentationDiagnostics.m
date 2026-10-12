#import "NWPresentationDiagnostics.h"
#import "NWDiagnosticReport.h"
#import "NWMainTabs.h"
#import "NWResources.h"
#include <math.h>

static NSUInteger recorded;
static NSUInteger activations;
static void (^reconcileRoot)(UIViewController *root);
static NSArray *rectValues(CGRect rect) {
    CGFloat values[] = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
    NSMutableArray *result = [NSMutableArray new];
    for (NSUInteger i = 0; i < 4; ++i) [result addObject:isfinite(values[i]) ? @(values[i]) : @0];
    return result;
}
static void describeController(UIViewController *controller, NSInteger parent, NSUInteger depth, NSUInteger maximumNodes, NSMutableArray *nodes) {
    if (!controller || depth > 8 || nodes.count >= maximumNodes) return;
    NSUInteger identifier = nodes.count;
    NSString *name = NSStringFromClass(controller.class);
    NSMutableDictionary *node = [@{@"id": @(identifier), @"parent": @(parent),
        @"class": [name substringToIndex:MIN(name.length, (NSUInteger)96)],
        @"loaded": @(controller.isViewLoaded), @"children": @(controller.childViewControllers.count),
        @"horizontal_size_class": @(controller.traitCollection.horizontalSizeClass)} mutableCopy];
    UITraitCollection *override = [controller.parentViewController overrideTraitCollectionForChildViewController:controller];
    if (override) node[@"parent_override_horizontal_size_class"] = @(override.horizontalSizeClass);
    if (controller.isViewLoaded) {
        UIView *view = controller.view;
        node[@"frame"] = rectValues(view.frame); node[@"bounds"] = rectValues(view.bounds);
        node[@"hidden"] = @(view.hidden); node[@"alpha"] = @(view.alpha);
        node[@"attached"] = @(view.window != nil);
        node[@"view_horizontal_size_class"] = @(view.traitCollection.horizontalSizeClass);
    }
    if ([controller isKindOfClass:UISplitViewController.class]) {
        UISplitViewController *split = (UISplitViewController *)controller;
        node[@"split_collapsed"] = @(split.collapsed);
        node[@"split_display_mode"] = @(split.displayMode);
        node[@"split_preferred_mode"] = @(split.preferredDisplayMode);
    }
    [nodes addObject:node];
    NSMutableArray *children = [controller.childViewControllers mutableCopy];
    UIViewController *selected = nil;
    if ([controller isKindOfClass:UITabBarController.class]) selected = ((UITabBarController *)controller).selectedViewController;
    if ([controller isKindOfClass:UINavigationController.class]) selected = ((UINavigationController *)controller).topViewController;
    if (selected && [children containsObject:selected]) { [children removeObject:selected]; [children insertObject:selected atIndex:0]; }
    for (UIViewController *child in children) describeController(child, (NSInteger)identifier, depth + 1, maximumNodes, nodes);
    describeController(controller.presentedViewController, (NSInteger)identifier, depth + 1, maximumNodes, nodes);
}
static NSArray<UIWindow *> *visibleWindows(void) {
    NSMutableArray *windows = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached ||
            scene.activationState == UISceneActivationStateBackground) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || !window.rootViewController) continue;
            if (window.isKeyWindow) [windows insertObject:window atIndex:0]; else [windows addObject:window];
        }
    }
    return windows;
}
static NSDictionary *presentationSnapshot(NSString *phase) {
    NSMutableArray *windows = [NSMutableArray new];
    NSArray *visible = visibleWindows();
    for (UIWindow *window in visible) {
        if (windows.count >= 2) break;
        NSMutableArray *nodes = [NSMutableArray new];
        describeController(window.rootViewController, -1, 0, visible.count > 1 ? 6 : 12, nodes);
        [windows addObject:@{@"key": @(window.isKeyWindow), @"level": @(window.windowLevel),
            @"bounds": rectValues(window.bounds), @"scene_state": @(window.windowScene.activationState),
            @"tabs": NWMainTabsPresentationSnapshot(NWFindMainTabs(window.rootViewController)), @"nodes": nodes}];
    }
    return @{@"review_id": @"ipad-presentation-v1", @"phase": phase, @"capture": @(recorded),
        @"ipad": @(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad),
        @"application_state": @(UIApplication.sharedApplication.applicationState),
        @"visible_windows": @(visible.count), @"windows": windows,
        @"limits": @{@"captures": @12, @"windows": @2, @"nodes_total": @12, @"depth": @8}};
}
static void boundSnapshot(NSMutableDictionary *snapshot) {
    for (NSUInteger attempt = 0; attempt < 12; ++attempt) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
        if (data && data.length <= 7600) return;
        NSMutableArray *largest = nil;
        for (NSDictionary *window in snapshot[@"windows"])
            if ([window[@"nodes"] count] > largest.count) largest = window[@"nodes"];
        if (largest.count <= 1) return;
        [largest removeLastObject]; snapshot[@"nodes_truncated_for_size"] = @YES;
    }
}
static void capture(NSString *phase) {
    if (recorded >= 12 || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    ++recorded;
    NSMutableArray *before = [NSMutableArray new];
    for (UIWindow *window in visibleWindows()) if (window.isKeyWindow && reconcileRoot) {
        if (before.count >= 2) break;
        [before addObject:NWMainTabsPresentationSnapshot(NWFindMainTabs(window.rootViewController))];
        reconcileRoot(window.rootViewController);
    }
    NSMutableDictionary *snapshot = [presentationSnapshot(phase) mutableCopy];
    snapshot[@"before_reconcile_tabs"] = before;
    boundSnapshot(snapshot);
    BOOL missing = NO;
    if ([phase isEqual:@"startup-settled"]) {
        missing = YES;
        for (NSDictionary *window in snapshot[@"windows"]) if ([window[@"tabs"][@"found"] boolValue]) missing = NO;
    }
    NWDiagnosticRecord(@"ui_presentation", missing ? @"warning" : @"captured", snapshot);
}
void NWPresentationDiagnosticsInstall(void (^reconcile)(UIViewController *root)) {
    NSCAssert(NSThread.isMainThread, @"Presentation diagnostics require the main thread");
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reconcileRoot = [reconcile copy];
        NSURL *reviewURL = [NWResourceBundle() URLForResource:@"iPadPresentationReview" withExtension:@"json" subdirectory:@"Diagnostics"];
        NSData *reviewData = reviewURL ? [NSData dataWithContentsOfURL:reviewURL] : nil;
        id review = reviewData ? [NSJSONSerialization JSONObjectWithData:reviewData options:0 error:NULL] : nil;
        NWDiagnosticRecord(@"ui_review", [review isKindOfClass:NSDictionary.class] ? @"captured" : @"warning",
            [review isKindOfClass:NSDictionary.class] ? review : @{@"error_code": @"ui_review_resource_missing"});
        NSArray *phases = @[@"startup", @"startup-2s", @"startup-6s", @"startup-settled"];
        NSUInteger delays[] = {0, 2, 6, 12};
        for (NSUInteger i = 0; i < phases.count; ++i) {
            NSString *phase = phases[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delays[i] * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ capture(phase); });
        }
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            if (activations++ >= 4) return;
            capture(@"activation");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ capture(@"activation-settled"); });
        }];
    });
}
#ifdef NW_UI_TESTING
int NWPresentationDiagnosticsUIRegressionCheck(void) {
    UIViewController *root = [UIViewController new];
    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[[UIViewController new], [UIViewController new], [UIViewController new]];
    [root addChildViewController:tabs]; [tabs didMoveToParentViewController:root];
    if (NWFindMainTabs(root) != tabs || NWFindMainTabs(tabs.viewControllers[1]) != tabs || NWFindMainTabs([UIViewController new])) return 110;
    NSMutableDictionary *snapshot = [presentationSnapshot(@"ui-regression") mutableCopy];
    boundSnapshot(snapshot);
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:NULL];
    if (!data || data.length > 8192 || ![snapshot[@"windows"] count]) return 111;
    BOOL found = NO;
    for (NSDictionary *window in snapshot[@"windows"]) {
        if ([window[@"nodes"] count] > 12) return 112;
        if ([window[@"tabs"][@"found"] boolValue] && [window[@"tabs"][@"presentation_items"] integerValue] == 4) found = YES;
    }
    if (!found) return 113;
    BOOL reviewFound = NO;
    for (NSDictionary *event in NWDiagnosticSnapshot()[@"events"])
        if ([event[@"test"] isEqual:@"ui_review"] && [event[@"details"][@"review_id"] isEqual:@"ipad-presentation-v1"]) reviewFound = YES;
    if (!reviewFound) return 116;
    NWDiagnosticRecord(@"ui_presentation", @"captured", snapshot);
    NSDictionary *latest = [NWDiagnosticSnapshot()[@"events"] lastObject];
    if (![latest[@"test"] isEqual:@"ui_presentation"] || latest[@"details"][@"truncated"] || !latest[@"details"][@"windows"]) return 114;
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (![data writeToURL:[documents URLByAppendingPathComponent:@"presentation-diagnostics.json"] atomically:YES]) return 115;
    return 0;
}
#endif
