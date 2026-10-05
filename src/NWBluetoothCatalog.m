#import "NWBluetoothCatalog.h"
#import "NWDeviceCatalog.h"
#import "NWAppearance.h"
#import "NWResources.h"
#include <stdlib.h>

@interface NWBluetoothCatalogViewController : UITableViewController
@property(nonatomic) NSUInteger platform;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *previousRanks;
@property(nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *models;
- (void)generateModels;
- (void)platformChanged:(UISegmentedControl *)sender;
@end

@implementation NWBluetoothCatalogViewController
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _previousRanks = [@[@(-1), @(-1), @(-1)] mutableCopy]; [self generateModels]; }
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
    [self refresh:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar);
}
- (void)refresh:(NSNotification *)notification {
    (void)notification;
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    [self.tableView reloadData];
}
- (void)generateModels {
    if (self.platform >= 3) return;
    int previous = self.previousRanks[self.platform].intValue;
    unsigned rank = NWCatalogNextRank(arc4random_uniform(previous < 0 ? NW_CATALOG_COMBINATIONS : NW_CATALOG_COMBINATIONS - 1), previous);
    unsigned selected[NW_CATALOG_SELECTION];
    if (!NWCatalogCombination(rank, selected)) return;
    NSMutableArray *models = [NSMutableArray new];
    for (unsigned i = 0; i < NW_CATALOG_SELECTION; ++i)
        [models addObject:@{@"name": @(NWCatalogModel((unsigned)self.platform, selected[i])),
            @"identity": [@"NWLab-" stringByAppendingString:NSUUID.UUID.UUIDString]}];
    self.models = models; self.previousRanks[self.platform] = @(rank);
    if (self.isViewLoaded) {
        [self refresh:nil];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"bt.catalog.generated"));
    }
}
- (void)platformChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= 3 ||
        (NSUInteger)sender.selectedSegmentIndex == self.platform) return;
    self.platform = (NSUInteger)sender.selectedSegmentIndex; [self generateModels];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? 2 : self.models.count;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; return NWText(section == 0 ? @"bt.catalog.platform" : @"bt.catalog.selection");
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; return NWText(section == 0 ? @"bt.catalog.hint" : @"bt.catalog.local_only");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (index.section == 0 && index.row == 0) {
        UISegmentedControl *platform = [[UISegmentedControl alloc] initWithItems:@[@"Apple", @"Google", @"Microsoft"]];
        platform.selectedSegmentIndex = self.platform;
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
    if (index.section == 0) {
        content.text = NWText(@"bt.catalog.generate");
        content.secondaryText = NWText(@"bt.catalog.generate_hint");
        content.image = [UIImage systemImageNamed:@"shuffle"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        cell.accessibilityIdentifier = @"nw.catalog.generate";
    } else {
        NSDictionary *model = self.models[index.row];
        content.text = model[@"name"];
        content.secondaryText = [NSString stringWithFormat:NWText(@"bt.catalog.identity"), model[@"identity"]];
        content.image = [UIImage systemImageNamed:@"cube.transparent"];
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"nw.catalog.model.%ld", (long)index.row];
    }
    content.imageProperties.tintColor = NWAccentColor(); cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (index.section == 0 && index.row == 1) [self generateModels];
}
@end

UIViewController *NWBluetoothCatalogController(void) { return [NWBluetoothCatalogViewController new]; }

#ifdef NW_UI_TESTING
int NWBluetoothCatalogUIRegressionPresent(int platform) {
    if (platform < 0 || platform >= 3) return 1;
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
                controller = [NWBluetoothCatalogViewController new];
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
    for (NSUInteger platform = 0; platform < 3; ++platform) {
        UISegmentedControl *selector = [[UISegmentedControl alloc] initWithItems:@[@"Apple", @"Google", @"Microsoft"]];
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
                if (![content.text isEqual:after[row]] || ![content.secondaryText containsString:@"NWLab-"] ||
                    cell.selectionStyle != UITableViewCellSelectionStyleNone) return 4;
                BOOL belongs = NO;
                for (unsigned model = 0; model < NW_CATALOG_MODELS; ++model)
                    if ([after[row] isEqual:@(NWCatalogModel((unsigned)platform, model))]) belongs = YES;
                if (!belongs) return 5;
            }
        }
    }
    if (controller.navigationItem.rightBarButtonItem ||
        ![[controller tableView:controller.tableView titleForFooterInSection:1] isEqual:NWText(@"bt.catalog.local_only")]) return 6;
    return 0;
}
#endif
