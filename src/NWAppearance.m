#import "NWAppearance.h"
#import "NWResources.h"

NSNotificationName const NWAppearanceChanged = @"NukeWirelessAppearanceChanged";
static NSString *const accentKey = @"NukeWirelessAccent";
static NSString *accent;
static NSArray<NSString *> *choices(void) { return @[@"cyan", @"violet", @"green"]; }
NSString *NWAccentName(void) {
    NSCAssert(NSThread.isMainThread, @"Appearance preferences belong to main");
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id saved = [NSUserDefaults.standardUserDefaults objectForKey:accentKey];
        accent = [saved isKindOfClass:NSString.class] && [choices() containsObject:saved] ? [saved copy] : @"cyan";
    });
    return accent;
}
BOOL NWSetAccent(NSString *name) {
    if (!NSThread.isMainThread || ![choices() containsObject:name]) return NO;
    if ([NWAccentName() isEqualToString:name]) return YES;
    accent = [name copy];
    [NSUserDefaults.standardUserDefaults setObject:accent forKey:accentKey];
    [NSNotificationCenter.defaultCenter postNotificationName:NWAppearanceChanged object:nil];
    return YES;
}
UIColor *NWAccentColor(void) {
    NSString *name = NWAccentName();
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
        if ([name isEqualToString:@"violet"])
            return dark ? [UIColor colorWithRed:0.69 green:0.49 blue:1 alpha:1] : UIColor.systemPurpleColor;
        if ([name isEqualToString:@"green"])
            return dark ? [UIColor colorWithRed:0.24 green:0.89 blue:0.66 alpha:1] : [UIColor colorWithRed:0.02 green:0.48 blue:0.29 alpha:1];
        return dark ? [UIColor colorWithRed:0.22 green:0.74 blue:1 alpha:1] : UIColor.systemBlueColor;
    }];
}
UIColor *NWCanvasColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:0.025 green:0.045 blue:0.085 alpha:1] :
            [UIColor colorWithRed:0.94 green:0.96 blue:0.99 alpha:1];
    }];
}
UIColor *NWPanelColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:0.065 green:0.09 blue:0.14 alpha:1] : UIColor.whiteColor;
    }];
}
void NWStyleCell(UITableViewCell *cell) {
    UIBackgroundConfiguration *background = UIBackgroundConfiguration.listGroupedCellConfiguration;
    background.backgroundColor = NWPanelColor();
    background.strokeColor = [NWAccentColor() colorWithAlphaComponent:0.16];
    background.strokeWidth = 0.5;
    cell.backgroundConfiguration = background; cell.tintColor = NWAccentColor();
}
void NWStyleNavigationBar(UINavigationBar *bar) {
    if (!bar) return;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    appearance.backgroundColor = NWCanvasColor();
    appearance.shadowColor = [NWAccentColor() colorWithAlphaComponent:0.18];
    UIColor *titleColor = [UIColor.labelColor resolvedColorWithTraitCollection:bar.traitCollection];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName:titleColor};
    appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName:titleColor,
        NSFontAttributeName:[[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:
            [UIFont systemFontOfSize:34 weight:UIFontWeightBold]]};
    bar.standardAppearance = appearance; bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance; bar.tintColor = NWAccentColor();
}

@interface NWAppearanceController : UITableViewController
@end
@implementation NWAppearanceController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"appearance.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 54;
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; (void)section; return choices().count;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; (void)section; return NWText(@"appearance.hint");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    NSString *name = choices()[index.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell);
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = NWText([@"appearance." stringByAppendingString:name]);
    content.image = [UIImage systemImageNamed:@"circle.fill"];
    content.imageProperties.tintColor = [name isEqualToString:@"violet"] ? UIColor.systemPurpleColor :
        ([name isEqualToString:@"green"] ? UIColor.systemGreenColor : UIColor.systemTealColor);
    cell.contentConfiguration = content;
    cell.accessoryType = [NWAccentName() isEqualToString:name] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits |= [NWAccentName() isEqualToString:name] ? UIAccessibilityTraitSelected : 0;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; NWSetAccent(choices()[index.row]);
    self.tableView.tintColor = NWAccentColor(); [self.tableView reloadData];
}
@end
UIViewController *NWAppearanceSettingsController(void) { return [NWAppearanceController new]; }
