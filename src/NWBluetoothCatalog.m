#import "NWBluetoothCatalog.h"
#import "NWDeviceCatalog.h"
#import "NWCatalogProfiles.h"
#import "NWBluetooth.h"
#import "NWAppearance.h"
#import "NWResources.h"
#include <stdlib.h>

@interface NWBluetoothCatalogViewController : UITableViewController
@property(nonatomic) NSUInteger platform;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *previousRanks;
@property(nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *models;
@property(nonatomic) BOOL emissionAvailable;
@property(nonatomic, copy) void (^emit)(NSUInteger platform, NSArray<NSNumber *> *models);
- (void)generateModels;
- (void)platformChanged:(UISegmentedControl *)sender;
- (NSArray<NSNumber *> *)emissionModels;
- (NSString *)profileIdentity:(unsigned)model;
@end

@implementation NWBluetoothCatalogViewController
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _previousRanks = [NSMutableArray new]; for (unsigned i = 0; i < NW_CATALOG_PLATFORMS; ++i) [_previousRanks addObject:@(-1)]; [self generateModels]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NWText(@"bt.catalog.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:)
        name:NWAppearanceChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:)
        name:UIContentSizeCategoryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:)
        name:NWBluetoothChanged object:nil];
    [self refresh:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self refresh:nil];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!self.isViewLoaded || ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh:nil]; });
}
- (void)refresh:(NSNotification *)notification {
    (void)notification;
    NWStyleNavigationBar(self.navigationController.navigationBar);
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    BOOL busy = NWBluetoothBusy(), stopping = NWBluetoothStopping();
    self.navigationItem.hidesBackButton = busy;
    self.navigationController.interactivePopGestureRecognizer.enabled = !busy;
    UIBarButtonItem *action = busy ? [[UIBarButtonItem alloc] initWithTitle:NWText(stopping ? @"bt.stopping" : @"bt.stop")
        style:UIBarButtonItemStylePlain target:self action:@selector(stopEmission)] :
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"questionmark.circle"]
        style:UIBarButtonItemStylePlain target:self action:@selector(showHelp)];
    action.enabled = !busy || !stopping;
    action.tintColor = busy ? UIColor.systemRedColor : NWAccentColor();
    action.accessibilityLabel = NWText(busy ? (stopping ? @"bt.stopping" : @"bt.stop") : @"bt.ui.help_title");
    action.accessibilityIdentifier = busy ? @"nw.catalog.stop" : @"nw.catalog.help";
    self.navigationItem.rightBarButtonItem = action;
    [self.tableView reloadData];
}
- (void)stopEmission { NWBluetoothStop(); }
- (void)showHelp {
    if (NWBluetoothBusy() || self.presentedViewController) return;
    UIAlertController *help = [UIAlertController alertControllerWithTitle:NWText(@"bt.catalog.title")
        message:NWText(@"bt.catalog.help") preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
}
- (void)generateModels {
    if (NWBluetoothBusy()) return;
    if (self.platform >= NW_CATALOG_PLATFORMS) return;
    int previous = self.previousRanks[self.platform].intValue;
    unsigned rank = NWCatalogNextRank(arc4random_uniform(previous < 0 ? NW_CATALOG_COMBINATIONS : NW_CATALOG_COMBINATIONS - 1), previous);
    unsigned selected[NW_CATALOG_SELECTION];
    if (!NWCatalogCombination(rank, selected)) return;
    NSMutableArray *models = [NSMutableArray new];
    for (unsigned i = 0; i < NW_CATALOG_SELECTION; ++i)
        [models addObject:@{@"name": @(NWCatalogModel((unsigned)self.platform, selected[i])), @"model": @(selected[i]),
            @"identity": [@"NWLab-" stringByAppendingString:NSUUID.UUID.UUIDString]}];
    self.models = models; self.previousRanks[self.platform] = @(rank);
    if (self.isViewLoaded) {
        [self refresh:nil];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"bt.catalog.generated"));
    }
}
- (void)platformChanged:(UISegmentedControl *)sender {
    if (NWBluetoothBusy()) return;
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= NW_CATALOG_PLATFORMS ||
        (NSUInteger)sender.selectedSegmentIndex == self.platform) return;
    self.platform = (NSUInteger)sender.selectedSegmentIndex; [self generateModels];
}
- (NSString *)profileIdentity:(unsigned)model {
    if (!NWCatalogProfileAvailable((unsigned)self.platform, model)) return NWText(@"bt.catalog.profile_unavailable");
    if (self.platform == 2) return @"Swift Pair · Display Name";
    uint32_t product = NWCatalogProfileID((unsigned)self.platform, model);
    if (self.platform == 0) return [NSString stringWithFormat:@"Apple · 0x%04X", (unsigned)product];
    return [NSString stringWithFormat:@"%@ · %06X", self.platform == 1 ? @"Fast Pair" : @"EasySetup", (unsigned)product];
}
- (NSArray<NSNumber *> *)emissionModels {
    NSMutableArray *models = [NSMutableArray new];
    for (NSDictionary *model in self.models)
        if (NWCatalogProfileAvailable((unsigned)self.platform, [model[@"model"] unsignedIntValue])) [models addObject:model[@"model"]];
    return [models copy];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return NWBluetoothEmissionIssue() ? 3 : 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? 3 : section == 1 ? self.models.count : (NWBluetoothEmissionIssue() ? 1 : 0);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; return NWText(section == 0 ? @"bt.catalog.platform" : section == 1 ? @"bt.catalog.selection" : @"bt.ui.attention");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; return section == 0 ? NWText(@"bt.ui.emission_hint") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (index.section == 0 && index.row == 0) {
        UISegmentedControl *platform = [[UISegmentedControl alloc] initWithItems:@[@"Apple", @"Google", @"Microsoft", @"Samsung"]];
        platform.selectedSegmentIndex = self.platform;
        platform.enabled = !NWBluetoothBusy();
        platform.accessibilityIdentifier = @"nw.catalog.platform";
        platform.accessibilityLabel = NWText(@"bt.catalog.platform");
        [platform addTarget:self action:@selector(platformChanged:) forControlEvents:UIControlEventValueChanged];
        platform.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:platform];
        [NSLayoutConstraint activateConstraints:@[
            [platform.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [platform.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [platform.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:16],
            [platform.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-16]]];
        return cell;
    }
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    if (index.section == 0 && index.row == 2) {
        NSUInteger count = self.emissionModels.count;
        BOOL busy = NWBluetoothBusy(), stopping = NWBluetoothStopping();
        BOOL enabled = busy ? !stopping : self.emissionAvailable && self.emit && count;
        content.text = busy ? NWText(stopping ? @"bt.stopping" : @"bt.stop") :
            [NSString stringWithFormat:NWText(@"bt.catalog.emit"), (unsigned long)count];
        content.secondaryText = busy ? NWText(stopping ? @"bt.ui.restoring" : @"bt.lab.running") :
            NWText(!self.emissionAvailable || !self.emit ? @"bt.catalog.worker_required" :
                count == 3 ? @"bt.catalog.emit_hint" : @"bt.catalog.partial");
        content.image = [UIImage systemImageNamed:busy ? @"stop.circle.fill" : @"play.circle.fill"];
        content.textProperties.color = busy ? UIColor.systemRedColor : enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
        if (busy) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating]; cell.accessoryView = spinner;
        }
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        if (!enabled) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        cell.accessibilityIdentifier = @"nw.catalog.emit";
    } else if (index.section == 0) {
        content.text = NWText(@"bt.catalog.generate");
        content.secondaryText = NWText(@"bt.catalog.generate_hint");
        content.image = [UIImage systemImageNamed:@"shuffle"];
        cell.selectionStyle = NWBluetoothBusy() ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        if (NWBluetoothBusy()) {
            cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
            content.textProperties.color = UIColor.secondaryLabelColor;
        }
        cell.accessibilityIdentifier = @"nw.catalog.generate";
    } else if (index.section == 1) {
        NSDictionary *model = self.models[index.row];
        content.text = model[@"name"];
        unsigned modelIndex = [model[@"model"] unsignedIntValue];
        content.secondaryText = [self profileIdentity:modelIndex];
        content.image = [UIImage systemImageNamed:self.platform == 2 ? @"desktopcomputer" : @"headphones"];
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"nw.catalog.model.%ld", (long)index.row];
    } else {
        content.text = NWBluetoothEmissionIssue();
        content.image = [UIImage systemImageNamed:@"exclamationmark.circle"];
        cell.accessibilityIdentifier = @"nw.catalog.issue";
    }
    content.imageProperties.tintColor = index.section == 2 ? UIColor.systemOrangeColor :
        index.section == 0 && NWBluetoothBusy() ? (index.row == 2 ? UIColor.systemRedColor : UIColor.tertiaryLabelColor) : NWAccentColor();
    cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section == 0 && index.row == 2 && NWBluetoothBusy()) { NWBluetoothStop(); return; }
    if (NWBluetoothBusy()) return;
    if (index.section == 0 && index.row == 1) [self generateModels];
    else if (index.section == 0 && index.row == 2 && self.emissionAvailable && self.emit) {
        NSArray *models = self.emissionModels;
        if (models.count) self.emit(self.platform, models);
    }
}
@end

UIViewController *NWBluetoothCatalogController(void) { return [NWBluetoothCatalogViewController new]; }
UIViewController *NWBluetoothCatalogControllerWithEmitter(BOOL available,
    void (^emit)(NSUInteger platform, NSArray<NSNumber *> *models)) {
    NWBluetoothCatalogViewController *controller = [NWBluetoothCatalogViewController new];
    controller.emissionAvailable = available; controller.emit = emit; return controller;
}

#ifdef NW_UI_TESTING
int NWBluetoothCatalogUIRegressionPresent(int platform) {
    if (platform < 0 || platform >= NW_CATALOG_PLATFORMS) return 1;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *root = window.rootViewController;
            UINavigationController *navigation = (UINavigationController *)root.presentedViewController;
            NWBluetoothCatalogViewController *controller;
            if ([navigation isKindOfClass:UINavigationController.class] &&
                [navigation.topViewController isKindOfClass:NWBluetoothCatalogViewController.class])
                controller = (NWBluetoothCatalogViewController *)navigation.topViewController;
            else {
                if (root.presentedViewController) return 2;
                // Simulator fixture: enable the action without invoking any radio backend.
                controller = (NWBluetoothCatalogViewController *)NWBluetoothCatalogControllerWithEmitter(YES,
                    ^(NSUInteger selectedPlatform, NSArray<NSNumber *> *models) { (void)selectedPlatform; (void)models; });
                navigation = [[UINavigationController alloc] initWithRootViewController:controller];
                navigation.modalPresentationStyle = UIModalPresentationFullScreen;
                [root presentViewController:navigation animated:NO completion:nil];
            }
            controller.platform = (NSUInteger)platform; [controller generateModels]; return 0;
        }
    }
    return 3;
}
int NWBluetoothCatalogUIRegressionCheck(void) {
    NWBluetoothCatalogViewController *controller = [NWBluetoothCatalogViewController new];
    [controller loadViewIfNeeded];
    for (NSUInteger platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        UISegmentedControl *selector = [[UISegmentedControl alloc] initWithItems:@[@"Apple", @"Google", @"Microsoft", @"Samsung"]];
        selector.selectedSegmentIndex = platform;
        [controller platformChanged:selector];
        if (controller.platform != platform || controller.models.count != 3) return 1;
        for (unsigned attempt = 0; attempt < 25; ++attempt) {
            NSArray *before = [controller.models valueForKey:@"name"];
            NSArray *identities = [controller.models valueForKey:@"identity"];
            [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
            NSArray *after = [controller.models valueForKey:@"name"];
            if (after.count != 3 || [NSSet setWithArray:after].count != 3 || [before isEqual:after]) return 2;
            if ([identities isEqual:[controller.models valueForKey:@"identity"]]) return 3;
            for (NSUInteger row = 0; row < 3; ++row) {
                UITableViewCell *cell = [controller tableView:controller.tableView cellForRowAtIndexPath:
                    [NSIndexPath indexPathForRow:row inSection:1]];
                UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
                if (![content.text isEqual:after[row]] || ![content.secondaryText containsString:[controller profileIdentity:[controller.models[row][@"model"] unsignedIntValue]]] ||
                    cell.selectionStyle != UITableViewCellSelectionStyleNone) return 4;
                BOOL belongs = NO;
                for (unsigned model = 0; model < NW_CATALOG_MODELS; ++model)
                    if ([after[row] isEqual:@(NWCatalogModel((unsigned)platform, model))]) belongs = YES;
                if (!belongs) return 5;
            }
        }
    }
    if (![controller.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.catalog.help"] ||
        [controller tableView:controller.tableView titleForFooterInSection:1]) return 6;
    NSIndexPath *emitIndex = [NSIndexPath indexPathForRow:2 inSection:0];
    UITableViewCell *emitCell = [controller tableView:controller.tableView cellForRowAtIndexPath:emitIndex];
    if (emitCell.selectionStyle != UITableViewCellSelectionStyleNone) return 7;
    __block NSUInteger calls = 0, emittedPlatform = NSNotFound; __block NSArray *emitted = nil;
    controller.emissionAvailable = YES;
    controller.emit = ^(NSUInteger platform, NSArray<NSNumber *> *models) { calls++; emittedPlatform = platform; emitted = models; };
    for (NSUInteger platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        controller.platform = platform;
        for (unsigned rank = 0; rank < NW_CATALOG_COMBINATIONS; ++rank) {
            unsigned selected[3]; NWCatalogCombination(rank, selected);
            NSMutableArray *fixtures = [NSMutableArray new], *expected = [NSMutableArray new];
            for (unsigned i = 0; i < 3; ++i) {
                [fixtures addObject:@{@"model": @(selected[i]), @"name": @(NWCatalogModel((unsigned)platform, selected[i])), @"identity": @"NWLab-12345678-1234"}];
                if (NWCatalogProfileAvailable((unsigned)platform, selected[i])) [expected addObject:@(selected[i])];
            }
            controller.models = fixtures;
            NSUInteger before = calls;
            [controller tableView:controller.tableView didSelectRowAtIndexPath:emitIndex];
            if (expected.count ? calls != before + 1 || emittedPlatform != platform || ![emitted isEqual:expected] : calls != before) return 8;
            emitCell = [controller tableView:controller.tableView cellForRowAtIndexPath:emitIndex];
            if ((emitCell.selectionStyle != UITableViewCellSelectionStyleNone) != (expected.count > 0)) return 9;
        }
    }
    return 0;
}
#endif
