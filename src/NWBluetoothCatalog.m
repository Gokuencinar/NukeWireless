#import "NWBluetoothCatalog.h"
#import "NWDeviceCatalog.h"
#import "NWCatalogProfiles.h"
#import "NWBluetooth.h"
#import "NWAppearance.h"
#import "NWResources.h"
#include <stdlib.h>

static UIImage *brandImage(NSString *name) {
    static NSMutableDictionary<NSString *, UIImage *> *images;
    if (!images) images = [NSMutableDictionary new];
    if (images[name]) return images[name];
    NSURL *url = [NWResourceBundle() URLForResource:name withExtension:@"pdf" subdirectory:@"brands"];
    if (!url) return nil;
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    if (!document) return nil;
    CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
    UIImage *image = nil;
    if (page) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
        image = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGContextTranslateCTM(context.CGContext, 0, 24); CGContextScaleCTM(context.CGContext, 1, -1);
            CGContextConcatCTM(context.CGContext, CGPDFPageGetDrawingTransform(page, kCGPDFMediaBox, CGRectMake(0, 0, 24, 24), 0, YES));
            CGContextDrawPDFPage(context.CGContext, page);
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    CGPDFDocumentRelease(document);
    if (image) images[name] = image;
    return image;
}
static NSArray<NSString *> *brandNames(void) { return @[@"Apple", @"Google", @"Microsoft", @"Samsung"]; }
static NSArray<NSString *> *brandAssets(void) { return @[@"apple", @"google", @"microsoft", @"samsung"]; }

@interface NWBluetoothCatalogViewController : UITableViewController
@property(nonatomic) NSUInteger platform;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *previousRanks;
@property(nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *models;
@property(nonatomic) BOOL emissionAvailable;
@property(nonatomic, copy) NSArray<NSNumber *> *emittingModels;
@property(nonatomic, copy) void (^emit)(NSUInteger platform, NSArray<NSNumber *> *models);
- (void)generateModels;
- (void)platformChanged:(UIButton *)sender;
- (NSArray<NSNumber *> *)emissionModels;
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
    if (!busy) self.emittingModels = nil;
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
    unsigned ranks[NW_CATALOG_COMBINATIONS];
    unsigned count = NWCatalogProfileRanks((unsigned)self.platform, ranks);
    if (!count) return;
    int previousOrdinal = -1;
    for (unsigned i = 0; i < count; ++i) if ((int)ranks[i] == previous) previousOrdinal = (int)i;
    // Exclude the preceding complete selection when alternatives exist.
    BOOL exclude = count > 1 && previousOrdinal >= 0;
    unsigned ordinal = arc4random_uniform(exclude ? count - 1 : count);
    if (exclude && ordinal >= (unsigned)previousOrdinal) ++ordinal;
    unsigned rank = ranks[ordinal];
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
- (void)platformChanged:(UIButton *)sender {
    if (NWBluetoothBusy() || sender.tag < 0 || sender.tag >= NW_CATALOG_PLATFORMS ||
        (NSUInteger)sender.tag == self.platform) return;
    self.platform = (NSUInteger)sender.tag; [self generateModels];
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
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    (void)table;
    if (section != 1) return nil;
    UITableViewHeaderFooterView *header = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration groupedHeaderConfiguration];
    content.text = NWText(@"bt.catalog.selection");
    content.image = brandImage(self.platform == 1 ? @"android" : brandAssets()[self.platform]);
    content.imageProperties.tintColor = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(18, 18);
    header.contentConfiguration = content; return header;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    if (section == 0) return NWText(@"bt.ui.emission_hint");
    return section == 1 && self.emissionAvailable && self.emit && !NWBluetoothBusy() ? NWText(@"bt.catalog.single_hint") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (index.section == 0 && index.row == 0) {
        UIStackView *selector = [[UIStackView alloc] init];
        selector.axis = UILayoutConstraintAxisVertical; selector.spacing = 8;
        selector.translatesAutoresizingMaskIntoConstraints = NO;
        NSUInteger columns = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? 1 : 2;
        for (NSUInteger row = 0; row < NW_CATALOG_PLATFORMS / columns; ++row) {
            UIStackView *pair = [[UIStackView alloc] init]; pair.spacing = 8; pair.distribution = UIStackViewDistributionFillEqually;
            for (NSUInteger column = 0; column < columns; ++column) {
                NSUInteger platform = row * columns + column;
                BOOL selected = platform == self.platform;
                UIButtonConfiguration *configuration = selected ? [UIButtonConfiguration tintedButtonConfiguration] : [UIButtonConfiguration plainButtonConfiguration];
                configuration.title = brandNames()[platform];
                configuration.subtitle = platform == 1 ? @"Android · Fast Pair" : platform == 2 ? @"Windows · Swift Pair" : platform == 3 ? @"Galaxy · EasySetup" : @"iPhone / iPad";
                configuration.image = brandImage(brandAssets()[platform]); configuration.imagePadding = 8;
                configuration.titleLineBreakMode = NSLineBreakByWordWrapping;
                configuration.subtitleLineBreakMode = NSLineBreakByWordWrapping;
                configuration.baseForegroundColor = selected ? NWAccentColor() : UIColor.labelColor;
                configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
                    NSMutableDictionary *result = [attributes mutableCopy];
                    result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; return result;
                };
                configuration.subtitleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
                    NSMutableDictionary *result = [attributes mutableCopy];
                    result[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2]; return result;
                };
                UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
                button.tag = platform; button.enabled = !NWBluetoothBusy();
                button.titleLabel.numberOfLines = 0;
                button.titleLabel.adjustsFontForContentSizeCategory = YES;
                button.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", configuration.title, configuration.subtitle];
                if (selected) button.accessibilityTraits |= UIAccessibilityTraitSelected;
                button.accessibilityIdentifier = [NSString stringWithFormat:@"nw.catalog.platform.%lu", (unsigned long)platform];
                [button.heightAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
                [button addTarget:self action:@selector(platformChanged:) forControlEvents:UIControlEventTouchUpInside];
                [pair addArrangedSubview:button];
            }
            [selector addArrangedSubview:pair];
        }
        [cell.contentView addSubview:selector];
        [NSLayoutConstraint activateConstraints:@[
            [selector.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [selector.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            [selector.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [selector.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
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
                count == self.models.count ? @"bt.catalog.emit_hint" : @"bt.catalog.partial");
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
        content.secondaryText = nil;
        content.image = [UIImage systemImageNamed:self.platform == 2 ? @"desktopcomputer" : @"headphones"];
        BOOL supported = NWCatalogProfileAvailable((unsigned)self.platform, modelIndex);
        BOOL busy = NWBluetoothBusy();
        BOOL enabled = self.emissionAvailable && self.emit && supported && !busy;
        BOOL active = busy && [self.emittingModels containsObject:model[@"model"]];
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        if (!enabled) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        cell.accessibilityHint = enabled ? NWText(@"bt.catalog.single_hint") : nil;
        if (active) {
            content.secondaryText = NWText(NWBluetoothStopping() ? @"bt.ui.restoring" : @"bt.lab.running");
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating]; cell.accessoryView = spinner;
        } else if (supported) {
            UIImageView *play = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle"]];
            play.tintColor = enabled ? NWAccentColor() : UIColor.tertiaryLabelColor;
            cell.accessoryView = play;
        }
        if (!supported) content.textProperties.color = UIColor.secondaryLabelColor;
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
        if (models.count) { self.emittingModels = models; self.emit(self.platform, models); }
    } else if (index.section == 1 && index.row >= 0 && (NSUInteger)index.row < self.models.count && self.emissionAvailable && self.emit) {
        NSNumber *model = self.models[index.row][@"model"];
        if (!NWCatalogProfileAvailable((unsigned)self.platform, model.unsignedIntValue)) return;
        self.emittingModels = @[model]; self.emit(self.platform, self.emittingModels);
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
int NWBluetoothCatalogUIRegressionSinglePresent(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UINavigationController *navigation = (UINavigationController *)window.rootViewController.presentedViewController;
            if (![navigation isKindOfClass:UINavigationController.class] ||
                ![navigation.topViewController isKindOfClass:NWBluetoothCatalogViewController.class]) return 1;
            NWBluetoothCatalogViewController *controller = (NWBluetoothCatalogViewController *)navigation.topViewController;
            NSArray *models = controller.emissionModels;
            if (!models.count) return 2;
            controller.emittingModels = @[models[0]];
            return NWBluetoothUIRegressionCatalogState(1);
        }
    }
    return 3;
}
int NWBluetoothCatalogUIRegressionCheck(void) {
    NWBluetoothCatalogViewController *controller = [NWBluetoothCatalogViewController new];
    [controller loadViewIfNeeded];
    for (NSString *asset in @[@"apple", @"google", @"microsoft", @"samsung", @"android"])
        if (!brandImage(asset)) return 13;
    UITableViewCell *brands = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UIStackView *selectorView = (UIStackView *)brands.contentView.subviews.firstObject;
    NSUInteger buttons = 0;
    for (UIStackView *pair in selectorView.arrangedSubviews) for (UIButton *button in pair.arrangedSubviews) {
        if (!button.configuration.image || !button.accessibilityLabel.length ||
            button.tag != (NSInteger)buttons) return 14;
        if (((button.accessibilityTraits & UIAccessibilityTraitSelected) != 0) != (buttons == controller.platform)) return 15;
        ++buttons;
    }
    if (buttons != NW_CATALOG_PLATFORMS) return 16;
    for (NSUInteger platform = 0; platform < NW_CATALOG_PLATFORMS; ++platform) {
        UIButton *selector = [UIButton new];
        selector.tag = platform;
        [controller platformChanged:selector];
        if (controller.platform != platform || controller.models.count != NW_CATALOG_SELECTION) return 1;
        for (unsigned attempt = 0; attempt < 25; ++attempt) {
            NSArray *before = [controller.models valueForKey:@"name"];
            NSArray *identities = [controller.models valueForKey:@"identity"];
            [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
            NSArray *after = [controller.models valueForKey:@"name"];
            unsigned ranks[NW_CATALOG_COMBINATIONS];
            if (after.count != NW_CATALOG_SELECTION || [NSSet setWithArray:after].count != NW_CATALOG_SELECTION ||
                (NWCatalogProfileRanks((unsigned)platform, ranks) > 1 && [before isEqual:after])) return 2;
            if ([identities isEqual:[controller.models valueForKey:@"identity"]]) return 3;
            for (NSUInteger row = 0; row < NW_CATALOG_SELECTION; ++row) {
                UITableViewCell *cell = [controller tableView:controller.tableView cellForRowAtIndexPath:
                    [NSIndexPath indexPathForRow:row inSection:1]];
                UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
                if (![content.text isEqual:after[row]] || content.secondaryText != nil ||
                    cell.selectionStyle != UITableViewCellSelectionStyleNone) return 4;
                BOOL belongs = NO;
                for (unsigned model = 0; model < NW_CATALOG_MODELS; ++model) {
                    const char *name = NWCatalogModel((unsigned)platform, model);
                    if (name && [after[row] isEqual:@(name)]) belongs = YES;
                }
                if (!belongs || !NWCatalogProfileAvailable((unsigned)platform, [controller.models[row][@"model"] unsignedIntValue])) return 5;
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
            unsigned selected[NW_CATALOG_SELECTION]; NWCatalogCombination(rank, selected);
            NSMutableArray *fixtures = [NSMutableArray new], *expected = [NSMutableArray new];
            for (unsigned i = 0; i < NW_CATALOG_SELECTION; ++i) {
                if (!NWCatalogModel((unsigned)platform, selected[i])) continue;
                [fixtures addObject:@{@"model": @(selected[i]), @"name": @(NWCatalogModel((unsigned)platform, selected[i])), @"identity": @"NWLab-12345678-1234"}];
                if (NWCatalogProfileAvailable((unsigned)platform, selected[i])) [expected addObject:@(selected[i])];
            }
            controller.models = fixtures;
            NSUInteger before = calls;
            [controller tableView:controller.tableView didSelectRowAtIndexPath:emitIndex];
            if (expected.count ? calls != before + 1 || emittedPlatform != platform || ![emitted isEqual:expected] : calls != before) return 8;
            emitCell = [controller tableView:controller.tableView cellForRowAtIndexPath:emitIndex];
            if ((emitCell.selectionStyle != UITableViewCellSelectionStyleNone) != (expected.count > 0)) return 9;
            for (NSUInteger row = 0; row < fixtures.count; ++row) {
                NSNumber *model = fixtures[row][@"model"];
                BOOL supported = NWCatalogProfileAvailable((unsigned)platform, model.unsignedIntValue);
                NSIndexPath *singleIndex = [NSIndexPath indexPathForRow:row inSection:1];
                UITableViewCell *single = [controller tableView:controller.tableView cellForRowAtIndexPath:singleIndex];
                if ((single.selectionStyle != UITableViewCellSelectionStyleNone) != supported ||
                    !(single.accessibilityTraits & UIAccessibilityTraitButton) ||
                    (supported && !single.accessoryView)) return 10;
                before = calls;
                [controller tableView:controller.tableView didSelectRowAtIndexPath:singleIndex];
                if (supported ? calls != before + 1 || emittedPlatform != platform || ![emitted isEqual:@[model]] : calls != before) return 11;
            }
        }
    }
    controller.emissionAvailable = NO;
    NSUInteger before = calls;
    [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    if (calls != before) return 12;
    return 0;
}
#endif
