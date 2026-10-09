#import "NWDeviceActions.h"
#import "NWAppearance.h"
#import "NWLanguage.h"
#import "NWResources.h"
#import <objc/runtime.h>

static char handlerKey, sheetKey;
@interface NWDeviceSheetReference : NSObject
@property(nonatomic,weak) UIViewController *controller;
@end
@implementation NWDeviceSheetReference
@end
void NWCaptureDeviceAction(UIAlertAction *action, void (^handler)(UIAlertAction *)) {
    if (handler) objc_setAssociatedObject(action, &handlerKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
static BOOL titleMatches(UIAlertAction *action, NSString *title) {
    return [action.title isEqual:NWNativeText(title)];
}
static BOOL isDeviceMenu(UIAlertController *menu) {
    if (menu.preferredStyle != UIAlertControllerStyleActionSheet) return NO;
    BOOL block = NO, rename = NO;
    for (UIAlertAction *action in menu.actions) {
        block |= titleMatches(action, @"Block Device") || titleMatches(action, @"Unblock Device");
        rename |= titleMatches(action, @"Rename Device");
        if (action.style != UIAlertActionStyleCancel && !objc_getAssociatedObject(action, &handlerKey)) return NO;
    }
    return block && rename;
}
@interface NWDeviceActionController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic,strong) UIAlertController *menu;
@property(nonatomic,strong) NSArray<UIAlertAction *> *items;
@property(nonatomic) BOOL invoked;
@end
@implementation NWDeviceActionController
- (instancetype)initWithMenu:(UIAlertController *)menu {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.menu = menu;
        NSMutableArray *items = [NSMutableArray new];
        for (UIAlertAction *action in menu.actions) if (action.style != UIAlertActionStyleCancel) [items addObject:action];
        self.items = items;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"device.actions");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:NWAppearanceChanged object:nil];
    [self restyle];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)restyle {
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    NWStyleNavigationBar(self.navigationController.navigationBar); [self.tableView reloadData];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous]; if (self.isViewLoaded) [self restyle];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; return section == 0 ? 1 : self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NWStyleCell(cell);
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if (index.section == 0) {
        content.text = self.menu.title; content.secondaryText = self.menu.message;
        content.image = [UIImage systemImageNamed:@"network"];
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityIdentifier = @"nw.device.identity";
    } else {
        UIAlertAction *action = self.items[index.row]; content.text = action.title;
        NSString *symbol = @"doc.on.doc";
        if (titleMatches(action, @"Block Device") || titleMatches(action, @"Unblock Device")) {
            symbol = titleMatches(action, @"Block Device") ? @"hand.raised.fill" : @"hand.raised.slash";
            content.secondaryText = NWText(titleMatches(action, @"Block Device") ? @"device.blockHint" : @"device.unblockHint");
        } else if (titleMatches(action, @"Rename Device")) {
            symbol = @"pencil"; content.secondaryText = NWText(@"device.renameHint");
        } else if (titleMatches(action, @"Clear Nickname")) symbol = @"arrow.uturn.backward";
        content.image = [UIImage systemImageNamed:symbol];
        UIColor *color = !action.enabled ? UIColor.secondaryLabelColor : action.style == UIAlertActionStyleDestructive ? UIColor.systemRedColor : UIColor.labelColor;
        content.textProperties.color = color; content.imageProperties.tintColor = action.enabled ? (action.style == UIAlertActionStyleDestructive ? UIColor.systemRedColor : NWAccentColor()) : UIColor.secondaryLabelColor;
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"nw.device.action.%ld", (long)index.row];
        if (!action.enabled) { cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled; }
        else cell.accessibilityTraits |= UIAccessibilityTraitButton;
    }
    cell.contentConfiguration = content; return cell;
}
- (void)invoke:(UIAlertAction *)action {
    if (self.invoked) return; self.invoked = YES;
    void (^handler)(UIAlertAction *) = action ? objc_getAssociatedObject(action, &handlerKey) : nil;
    if (handler) handler(action);
}
- (UIAlertAction *)cancelAction {
    for (UIAlertAction *action in self.menu.actions) if (action.style == UIAlertActionStyleCancel) return action;
    return nil;
}
- (void)close {
    [self dismissViewControllerAnimated:YES completion:^{ [self invoke:[self cancelAction]]; }];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentation {
    (void)presentation; [self invoke:[self cancelAction]];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; if (!index.section || self.invoked) return;
    UIAlertAction *action = self.items[index.row]; if (!action.enabled) return;
    [self dismissViewControllerAnimated:YES completion:^{ [self invoke:action]; }];
}
@end
static void (*oldPresent)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));
static void present(UIViewController *presenter, SEL selector, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    if ([controller isKindOfClass:UIAlertController.class] && isDeviceMenu((UIAlertController *)controller)) {
        NWDeviceActionController *sheet = [[NWDeviceActionController alloc] initWithMenu:(UIAlertController *)controller];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:sheet];
        navigation.modalPresentationStyle = UIModalPresentationPageSheet;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        navigation.sheetPresentationController.prefersGrabberVisible = YES; navigation.presentationController.delegate = sheet;
        // Weak backlink: the sheet retains the native menu and its public action handlers.
        NWDeviceSheetReference *reference = [NWDeviceSheetReference new]; reference.controller = navigation;
        objc_setAssociatedObject(controller, &sheetKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        oldPresent(presenter, selector, navigation, animated, completion); return;
    }
    oldPresent(presenter, selector, controller, animated, completion);
}
void NWInstallDeviceActionPresentation(void) {
    Method method = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
    if (method && !oldPresent) oldPresent = (void *)method_setImplementation(method, (IMP)present);
}
#ifdef NW_UI_TESTING
UIViewController *NWDeviceActionPresentedController(UIAlertController *menu) {
    NWDeviceSheetReference *value = objc_getAssociatedObject(menu, &sheetKey); return value.controller;
}
#endif
