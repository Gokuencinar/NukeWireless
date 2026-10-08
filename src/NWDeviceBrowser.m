#import "NWDeviceBrowser.h"
#import "NWScanBridge.h"
#import "NWResources.h"
#import "NWAppearance.h"
#import "NWLanguage.h"
#import <arpa/inet.h>

static NSString *const sortKey = @"NukeWirelessDeviceSort";
static NSString *const priorityKey = @"NukeWirelessDevicePriority";
static NSString *const filterKey = @"NukeWirelessDeviceFilter";
static NSArray<NSString *> *sortChoices(void) { return @[@"ip", @"name", @"vendor"]; }
static uint32_t addressNumber(NSString *text) {
    struct in_addr address;
    return inet_pton(AF_INET, text.UTF8String, &address) == 1 ? ntohl(address.s_addr) : UINT32_MAX;
}

@interface NWDeviceBrowserController : UITableViewController <UISearchResultsUpdating, UISearchBarDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *snapshot;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, copy) NSString *order;
@property (nonatomic, copy) NSString *gateway;
@property (nonatomic) BOOL priority;
@property (nonatomic) NSUInteger gatewayRequest;
@property (nonatomic) uint64_t gatewayGeneration;
@property (nonatomic) BOOL requestedGateway;
@property (nonatomic) BOOL snapshotScanning;
@property (nonatomic, strong) UIBarButtonItem *sortItem;
- (void)refreshSnapshot;
- (void)showDeviceActions:(NSDictionary *)row anchor:(UIView *)anchor;
- (void)showRename:(NSDictionary *)row;
- (void)renameFromMenu:(UIAlertController *)menu row:(NSDictionary *)row;
@end
static __weak NWDeviceBrowserController *visibleBrowser;
@implementation NWDeviceBrowserController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"browser.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 106;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.definesPresentationContext = YES;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:sortKey];
    self.order = [saved isKindOfClass:NSString.class] && [sortChoices() containsObject:saved] ? saved : @"ip";
    id priority = [defaults objectForKey:priorityKey];
    self.priority = [priority isKindOfClass:NSNumber.class] ? [priority boolValue] : YES;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self; self.search.searchBar.delegate = self;
    self.search.obscuresBackgroundDuringPresentation = NO; self.search.hidesNavigationBarDuringPresentation = NO;
    self.search.searchBar.placeholder = NWText(@"browser.search");
    self.search.searchBar.scopeButtonTitles = @[NWText(@"browser.all"), NWText(@"browser.blocked"), NWText(@"browser.unblocked")];
    self.search.searchBar.showsScopeBar = YES;
    id filter = [defaults objectForKey:filterKey];
    NSInteger selected = [filter isKindOfClass:NSNumber.class] ? [filter integerValue] : 0;
    self.search.searchBar.selectedScopeButtonIndex = selected >= 0 && selected < 3 ? selected : 0;
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NWText(@"browser.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(close:)];
    self.sortItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
        style:UIBarButtonItemStylePlain target:nil action:NULL];
    self.sortItem.accessibilityLabel = NWText(@"browser.sort"); self.navigationItem.rightBarButtonItem = self.sortItem;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stateChanged:) name:NWStateChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged:) name:NWAppearanceChanged object:nil];
    [self applyAppearance]; [self updateSortMenu]; [self refreshSnapshot]; [self refreshGateway];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; visibleBrowser = self; [self refreshSnapshot]; }
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated]; if (visibleBrowser == self) visibleBrowser = nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)close:(id)sender { (void)sender; self.search.active = NO; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)applyAppearance {
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    self.search.searchBar.tintColor = NWAccentColor(); NWStyleNavigationBar(self.navigationController.navigationBar);
}
- (void)appearanceChanged:(NSNotification *)notification {
    (void)notification; [self applyAppearance]; [self reloadKeepingPosition];
}
- (void)stateChanged:(NSNotification *)notification {
    (void)notification; [self refreshSnapshot];
    if (!NWScanBusy()) [self refreshGateway];
}
- (void)refreshGateway {
    uint64_t generation = NWDeviceGeneration();
    if (self.requestedGateway && self.gatewayGeneration == generation) return;
    self.requestedGateway = YES; self.gatewayGeneration = generation;
    NSUInteger request = ++self.gatewayRequest;
    __weak NWDeviceBrowserController *weakSelf = self;
    // Read-only use of the already present SystemConfiguration gateway reader.
    // No MobileWiFi, location authorization, probes or changes to scanner state.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *gateway = NWReadGatewayAddress();
        dispatch_async(dispatch_get_main_queue(), ^{
            NWDeviceBrowserController *controller = weakSelf;
            if (!controller || controller.gatewayRequest != request || NWDeviceGeneration() != generation) return;
            if (![(controller.gateway ?: @"") isEqualToString:(gateway ?: @"")]) {
                controller.gateway = gateway; [controller projectSnapshot];
            }
        });
    });
}
- (void)refreshSnapshot {
    NSArray *snapshot = NWDeviceSnapshot();
    BOOL scanning = NWScanBusy();
    if ([self.snapshot isEqualToArray:snapshot] && self.snapshotScanning == scanning) return;
    self.snapshotScanning = scanning;
    self.snapshot = snapshot; [self projectSnapshot];
}
- (NSInteger)rank:(NSDictionary *)row {
    if (!self.priority) return 0;
    if ([row[@"local"] boolValue]) return 0;
    return self.gateway.length && [row[@"ip"] isEqualToString:self.gateway] ? 1 : 2;
}
- (void)projectSnapshot {
    NSString *query = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSInteger filter = self.search.searchBar.selectedScopeButtonIndex;
    NSMutableArray *rows = [NSMutableArray new];
    for (NSDictionary *row in self.snapshot) {
        BOOL blocked = [row[@"blocked"] boolValue];
        if ((filter == 1 && !blocked) || (filter == 2 && blocked)) continue;
        BOOL match = !query.length;
        for (NSString *key in @[@"name", @"ip", @"mac", @"vendor"])
            if ([row[key] rangeOfString:query ?: @"" options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) match = YES;
        if (match) [rows addObject:row];
    }
    NSString *order = self.order;
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger first = [self rank:a], second = [self rank:b];
        if (first != second) return first < second ? NSOrderedAscending : NSOrderedDescending;
        if (![order isEqualToString:@"ip"]) {
            NSComparisonResult result = [a[order] localizedStandardCompare:b[order]];
            if (result != NSOrderedSame) return result;
        }
        uint32_t left = addressNumber(a[@"ip"]), right = addressNumber(b[@"ip"]);
        return left == right ? NSOrderedSame : (left < right ? NSOrderedAscending : NSOrderedDescending);
    }];
    self.rows = [rows copy]; [self reloadKeepingPosition];
}
- (void)reloadKeepingPosition {
    CGPoint position = self.tableView.contentOffset;
    [UIView performWithoutAnimation:^{
        [self.tableView reloadData]; [self.tableView layoutIfNeeded];
        CGFloat minimum = -self.tableView.adjustedContentInset.top;
        CGFloat maximum = MAX(minimum, self.tableView.contentSize.height - self.tableView.bounds.size.height + self.tableView.adjustedContentInset.bottom);
        self.tableView.contentOffset = CGPointMake(position.x, MIN(maximum, MAX(minimum, position.y)));
    }];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller { (void)controller; [self projectSnapshot]; }
- (void)searchBar:(UISearchBar *)bar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    (void)bar; [NSUserDefaults.standardUserDefaults setInteger:selectedScope forKey:filterKey]; [self projectSnapshot];
}
- (void)updateSortMenu {
    __weak NWDeviceBrowserController *weakSelf = self;
    NSMutableArray *orders = [NSMutableArray new];
    for (NSString *code in sortChoices()) {
        UIAction *action = [UIAction actionWithTitle:NWText([@"browser.sort." stringByAppendingString:code]) image:nil identifier:nil handler:^(UIAction *selected) {
            (void)selected; NWDeviceBrowserController *controller = weakSelf; if (!controller) return;
            controller.order = code; [NSUserDefaults.standardUserDefaults setObject:code forKey:sortKey];
            [controller updateSortMenu]; [controller projectSnapshot];
        }];
        action.state = [self.order isEqualToString:code] ? UIMenuElementStateOn : UIMenuElementStateOff; [orders addObject:action];
    }
    UIMenu *orderMenu = [UIMenu menuWithTitle:NWText(@"browser.sort") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:orders];
    UIAction *priority = [UIAction actionWithTitle:NWText(@"browser.priority") image:nil identifier:nil handler:^(UIAction *selected) {
        (void)selected; NWDeviceBrowserController *controller = weakSelf; if (!controller) return;
        controller.priority = !controller.priority; [NSUserDefaults.standardUserDefaults setBool:controller.priority forKey:priorityKey];
        [controller updateSortMenu]; [controller projectSnapshot];
    }];
    priority.state = self.priority ? UIMenuElementStateOn : UIMenuElementStateOff;
    self.sortItem.menu = [UIMenu menuWithTitle:@"" children:@[orderMenu, priority]];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return MAX((NSUInteger)1, self.rows.count); }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; (void)section;
    return [NSString stringWithFormat:NWText(@"browser.count"), (unsigned long)self.rows.count, (unsigned long)self.snapshot.count];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { (void)table; (void)section; return NWText(@"browser.hint"); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"NWBrowserDevice"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NWBrowserDevice"];
    NWStyleCell(cell); cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityTraits &= ~UIAccessibilityTraitButton;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    if (!self.rows.count) {
        content.text = NWText(self.snapshot.count ? @"browser.noMatches" : (NWScanBusy() ? @"scan.scanning" : @"browser.empty"));
        content.image = [UIImage systemImageNamed:@"magnifyingglass"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityHint = nil;
    } else {
        NSDictionary *row = self.rows[index.row]; BOOL blocked = [row[@"blocked"] boolValue];
        NSString *role = [row[@"local"] boolValue] ? NWText(@"browser.local") :
            (self.gateway.length && [row[@"ip"] isEqualToString:self.gateway] ? NWText(@"browser.router") : nil);
        content.text = row[@"name"];
        NSMutableArray *details = [NSMutableArray arrayWithObjects:row[@"ip"], nil];
        if ([row[@"mac"] length]) [details addObject:row[@"mac"]];
        if ([row[@"vendor"] length]) [details addObject:row[@"vendor"]];
        if (role) [details addObject:role];
        [details addObject:NWText(blocked ? @"browser.blocked" : @"browser.unblocked")];
        content.secondaryText = [details componentsJoinedByString:@"\n"];
        content.image = [UIImage systemImageNamed:blocked ? @"lock.fill" : @"wifi"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault; cell.accessibilityHint = NWText(@"browser.actionsHint");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
    }
    content.imageProperties.tintColor = NWAccentColor(); cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.row < 0 || index.row >= (NSInteger)self.rows.count) return;
    NSDictionary *row = [self.rows[index.row] copy];
    [self.search.searchBar endEditing:YES];
    [self.view endEditing:YES];
    [self showDeviceActions:row anchor:[table cellForRowAtIndexPath:index] ?: table];
}
- (UIViewController *)actionPresenter {
    // An active search owns a presentation; keep its text and results in place.
    UIViewController *presenter = self.presentedViewController ?: self;
    return ([presenter isKindOfClass:UISearchController.class] || presenter == self) &&
        !presenter.presentedViewController ? presenter : nil;
}
- (void)showActionFailure {
    UIViewController *presenter = [self actionPresenter];
    if (!presenter) {
        UIViewController *search = self.presentedViewController;
        UIViewController *alert = [search isKindOfClass:UISearchController.class] ? search.presentedViewController : search;
        if ([alert isKindOfClass:UIAlertController.class]) {
            [alert dismissViewControllerAnimated:YES completion:^{ [self showActionFailure]; }];
        }
        return;
    }
    if (!presenter.view.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"browser.actionFailed")
        message:NWText(@"browser.actionRetry") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (UIAlertController *)deviceMenu:(NSDictionary *)row anchor:(UIView *)anchor {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:row[@"name"]
        message:[NSString stringWithFormat:@"%@\n%@", row[@"ip"], row[@"mac"] ?: @""] preferredStyle:UIAlertControllerStyleActionSheet];
    __weak NWDeviceBrowserController *weakSelf = self;
    BOOL blocked = [row[@"blocked"] boolValue];
    UIAlertAction *toggle = [UIAlertAction actionWithTitle:NWNativeText(blocked ? @"Unblock Device" : @"Block Device")
        style:blocked ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            (void)action;
            if (!NWDeviceSetBlocked(row, !blocked, ^(BOOL success) {
                [weakSelf refreshSnapshot]; if (!success) [weakSelf showActionFailure];
            })) [weakSelf showActionFailure];
        }];
    toggle.enabled = NWDeviceCanSetBlocked(row, !blocked); [menu addAction:toggle];
    __weak UIAlertController *weakMenu = menu;
    UIAlertAction *rename = [UIAlertAction actionWithTitle:NWNativeText(@"Rename Device") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf renameFromMenu:weakMenu row:row];
    }];
    rename.enabled = NWDeviceCanRename(row); [menu addAction:rename];
    UIAlertAction *clear = [UIAlertAction actionWithTitle:NWNativeText(@"Clear Nickname") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        if (!NWDeviceSetNickname(row, nil)) [weakSelf showActionFailure];
        else [weakSelf refreshSnapshot];
    }];
    clear.enabled = rename.enabled && [row[@"nickname"] length] > 0; [menu addAction:clear];
    [menu addAction:[UIAlertAction actionWithTitle:NWText(@"browser.copyIP") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; UIPasteboard.generalPasteboard.string = row[@"ip"];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"browser.copied"));
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = anchor;
    menu.popoverPresentationController.sourceRect = anchor.bounds;
    return menu;
}
- (void)showDeviceActions:(NSDictionary *)row anchor:(UIView *)anchor {
    UIViewController *presenter = [self actionPresenter]; if (!presenter.view.window) return;
    [presenter presentViewController:[self deviceMenu:row anchor:anchor] animated:YES completion:nil];
}
- (void)renameFromMenu:(UIAlertController *)menu row:(NSDictionary *)row {
    [menu dismissViewControllerAnimated:YES completion:^{ [self showRename:row]; }];
}
- (void)showRename:(NSDictionary *)row {
    UIViewController *presenter = [self actionPresenter]; if (!presenter.view.window) return;
    UIAlertController *rename = [UIAlertController alertControllerWithTitle:NWNativeText(@"Rename Device")
        message:row[@"ip"] preferredStyle:UIAlertControllerStyleAlert];
    [rename addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = NWNativeText(@"Enter new name");
        field.text = [row[@"nickname"] length] ? row[@"nickname"] : row[@"name"];
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak NWDeviceBrowserController *weakSelf = self;
    __weak UIAlertController *weakRename = rename;
    [rename addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [rename addAction:[UIAlertAction actionWithTitle:NWText(@"browser.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *name = [weakRename.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!NWDeviceSetNickname(row, name.length ? name : nil)) [weakSelf showActionFailure];
        else [weakSelf refreshSnapshot];
    }]];
    [presenter presentViewController:rename animated:YES completion:nil];
}
@end
void NWPresentDeviceBrowser(UIViewController *presenter) {
    if (!NSThread.isMainThread || !presenter.view.window || presenter.presentedViewController) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[NWDeviceBrowserController new]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    navigation.sheetPresentationController.prefersGrabberVisible = YES;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
void NWRefreshVisibleDeviceBrowser(void) { if (visibleBrowser.view.window) [visibleBrowser refreshSnapshot]; }
#ifdef NW_UI_TESTING
// UIKit can hide the browser beneath search/alerts; the test follows the same
// retained controller even while viewDidDisappear clears the visible refresh target.
static __weak NWDeviceBrowserController *regressionBrowser;
int NWDeviceBrowserUIRegressionCheck(void) {
    if (NWDeviceActionsUIRegressionCheck()) return 1;
    NWBeginDeviceActionsUITest();
    @try {
        NWDeviceBrowserController *browser = [NWDeviceBrowserController new]; [browser loadViewIfNeeded];
        browser.search.searchBar.selectedScopeButtonIndex = 0;
        for (NSString *query in @[@"192.0.2.42", @"44:55", @"samsUNG"]) {
            browser.search.searchBar.text = query; [browser projectSnapshot];
            if (browser.rows.count != 1 || ![browser.rows.firstObject[@"ip"] isEqual:@"192.0.2.42"]) return 2;
            UITableViewCell *cell = [browser tableView:browser.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            if (cell.accessoryType != UITableViewCellAccessoryDisclosureIndicator ||
                ![cell.accessibilityHint isEqual:NWText(@"browser.actionsHint")]) return 3;
            UIAlertController *menu = [browser deviceMenu:browser.rows.firstObject anchor:cell];
            if (menu.actions.count != 5 || ![menu.actions[0].title isEqual:NWNativeText(@"Block Device")] ||
                !menu.actions[0].enabled || !menu.actions[1].enabled || menu.actions[2].enabled) return 4;
            if (!NWDeviceSetNickname(browser.rows.firstObject, @"Escritorio")) return 5;
            [browser refreshSnapshot];
            menu = [browser deviceMenu:browser.rows.firstObject anchor:cell];
            if (!menu.actions[2].enabled) return 6;
            NWDeviceSetNickname(browser.rows.firstObject, nil); [browser refreshSnapshot];
        }
        browser.search.searchBar.text = @"no-match"; [browser projectSnapshot];
        if (browser.rows.count) return 7;
        return 0;
    } @finally { NWEndDeviceActionsUITest(); }
}
int NWDeviceBrowserUIRegressionPresent(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *root = window.rootViewController;
            if (root.presentedViewController) return 1;
            NWBeginDeviceActionsUITest(); NWPresentDeviceBrowser(root); return 0;
        }
    }
    return 2;
}
int NWDeviceBrowserUIRegressionSearch(void) {
    NWDeviceBrowserController *browser = visibleBrowser;
    if (!browser.view.window) return 1;
    regressionBrowser = browser;
    browser.search.searchBar.selectedScopeButtonIndex = 0;
    browser.search.searchBar.text = @"44:55"; [browser projectSnapshot]; browser.search.active = YES;
    return browser.rows.count == 1 ? 0 : 2;
}
int NWDeviceBrowserUIRegressionSelect(void) {
    NWDeviceBrowserController *browser = visibleBrowser;
    if (!browser.view.window || !browser.search.active || browser.rows.count != 1) return 1;
    [browser tableView:browser.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    return 0;
}
int NWDeviceBrowserUIRegressionMenu(void) {
    NWDeviceBrowserController *browser = regressionBrowser;
    UIViewController *presented = browser.presentedViewController;
    if ([presented isKindOfClass:UISearchController.class]) presented = presented.presentedViewController;
    if (![presented isKindOfClass:UIAlertController.class] || !browser.search.active ||
        ![browser.search.searchBar.text isEqual:@"44:55"]) return 1;
    UIAlertController *menu = (UIAlertController *)presented;
    return menu.actions.count == 5 && [menu.title isEqual:@"Mesa"] && menu.actions[0].enabled ? 0 : 2;
}
int NWDeviceBrowserUIRegressionRename(void) {
    NWDeviceBrowserController *browser = regressionBrowser;
    UIViewController *presented = browser.presentedViewController;
    if ([presented isKindOfClass:UISearchController.class]) presented = presented.presentedViewController;
    if (![presented isKindOfClass:UIAlertController.class] || !browser.rows.count) return 1;
    [browser renameFromMenu:(UIAlertController *)presented row:browser.rows.firstObject];
    return 0;
}
int NWDeviceBrowserUIRegressionRenameCheck(void) {
    NWDeviceBrowserController *browser = regressionBrowser;
    UIViewController *presented = browser.presentedViewController;
    if ([presented isKindOfClass:UISearchController.class]) presented = presented.presentedViewController;
    if (![presented isKindOfClass:UIAlertController.class] || !browser.search.active ||
        ![browser.search.searchBar.text isEqual:@"44:55"]) return 1;
    UIAlertController *rename = (UIAlertController *)presented;
    return rename.preferredStyle == UIAlertControllerStyleAlert && rename.textFields.count == 1 &&
        [rename.title isEqual:NWNativeText(@"Rename Device")] &&
        [rename.textFields.firstObject.text isEqual:@"Mesa"] ? 0 : 2;
}
#endif
