#import "NWDiagnostics.h"
#import "NWDiagnosticReport.h"
#import "NWBuild.h"
#import "NWLegacyABI.h"
#import "NWResources.h"
#import "NWAppearance.h"
#import "NWScanBridge.h"
#import "NWBluetooth.h"
#import "NWBLE.h"
#import <CoreBluetooth/CoreBluetooth.h>
#include <sys/utsname.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <net/if.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static BOOL collecting;
static NSDictionary *environment(void) {
    struct utsname system = {0}; uname(&system);
    char build[64] = {0}; size_t size = sizeof build; sysctlbyname("kern.osversion", build, &size, NULL, 0);
    NSMutableDictionary *interfaces = [NSMutableDictionary new]; struct ifaddrs *list = NULL;
    if (!getifaddrs(&list)) {
        for (struct ifaddrs *p = list; p && interfaces.count < 24; p = p->ifa_next) {
            if (!p->ifa_addr || !p->ifa_name) continue;
            NSString *name = [NSString stringWithUTF8String:p->ifa_name];
            NSMutableDictionary *entry = interfaces[name] ?: [NSMutableDictionary new];
            entry[@"up"] = @((p->ifa_flags & IFF_UP) != 0);
            if (p->ifa_addr->sa_family == AF_INET) entry[@"ipv4_present"] = @YES;
            if (p->ifa_addr->sa_family == AF_INET6) entry[@"ipv6_present"] = @YES;
            interfaces[name] = entry;
        }
        freeifaddrs(list);
    }
    NSMutableArray *images = [NSMutableArray new];
    for (uint32_t i = 0; i < _dyld_image_count() && images.count < 16; ++i) {
        NSString *path = [NSString stringWithUTF8String:_dyld_get_image_name(i) ?: ""];
        if (![path.lastPathComponent hasPrefix:@"NukeWireless"] && ![path.lastPathComponent isEqual:@NWLegacyExecutable]) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64 || header->sizeofcmds > 1024 * 1024) continue;
        const uint8_t *cursor = (const void *)(header + 1), *end = cursor + header->sizeofcmds;
        NSMutableDictionary *image = [@{@"name": path.lastPathComponent, @"cpu_type": @(header->cputype), @"cpu_subtype": @(header->cpusubtype)} mutableCopy];
        for (uint32_t c = 0; c < header->ncmds && cursor + sizeof(struct load_command) <= end; ++c) {
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof *command || command->cmdsize > (uintptr_t)(end - cursor)) break;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuid = (const void *)cursor;
                image[@"macho_uuid"] = [[NSUUID alloc] initWithUUIDBytes:uuid->uuid].UUIDString;
            }
            cursor += command->cmdsize;
        }
        [images addObject:image];
    }
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return @{@"machine": [NSString stringWithUTF8String:system.machine], @"kernel_release": [NSString stringWithUTF8String:system.release],
        @"ios_version": NSProcessInfo.processInfo.operatingSystemVersionString, @"ios_build": [NSString stringWithUTF8String:build],
        @"process_bits": @(sizeof(void *) * 8), @"uid": @(getuid()), @"euid": @(geteuid()),
        @"bundle_id": NSBundle.mainBundle.bundleIdentifier ?: @"unknown", @"package_version": info[@"CFBundleShortVersionString"] ?: NW_BUILD_VERSION,
        @"bundle_version": info[@"CFBundleVersion"] ?: @"unknown", @"package_scheme": info[@"NukeWirelessPackageScheme"] ?: @"unknown",
        @"source_commit": info[@"NukeWirelessSourceCommit"] ?: @"unknown", @"expected_worker": info[@"NukeWirelessWorkerVersion"] ?: @"unknown",
        @"rootless_prefix_present": @([NSFileManager.defaultManager fileExistsAtPath:@"/var/jb"]),
        @"interfaces_without_addresses": interfaces, @"loaded_product_images": images,
        @"symbol_presence": @{@"MSHookFunction": @(dlsym(RTLD_DEFAULT, "MSHookFunction") != NULL)},
        @"presence_is_functional_proof": @NO};
}
static void collectEnvironment(void) {
    if (collecting) return; collecting = YES;
    NWDiagnosticRecord(@"environment", @"running", @{});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *details = environment();
        dispatch_async(dispatch_get_main_queue(), ^{
            NWDiagnosticRecord(@"environment", @"captured", details);
            NWDiagnosticRecord(@"wifi_state", @"captured", NWScanDiagnosticSnapshot());
            NWDiagnosticRecord(@"ble_permission", @"captured", @{@"authorization": @(CBManager.authorization), @"manager_created": @NO});
            NWBluetoothReadDiagnostics(^(NSDictionary *report) {
                collecting = NO;
                NWDiagnosticRecord(@"bluetooth_contract", report[@"error_code"] ? @"failed" : @"captured", report);
            });
        });
    });
}

@interface NWDiagnosticsViewController : UITableViewController
@property(nonatomic, strong) NSArray *events;
@property(nonatomic) BOOL exporting;
- (void)refresh;
@end
@implementation NWDiagnosticsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"diag.title");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70;
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    for (NSString *name in @[NWDiagnosticChanged, NWBluetoothChanged, NWStateChanged, NWAppearanceChanged])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:name object:nil];
    [self refresh];
}
- (void)changed:(NSNotification *)note { (void)note; [self refresh]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar); [self refresh]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded && [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        NWStyleNavigationBar(self.navigationController.navigationBar); [self.tableView reloadData];
    }
}
- (void)refresh {
    self.events = [[NWDiagnosticSnapshot()[@"events"] reverseObjectEnumerator] allObjects];
    [self.tableView reloadData]; self.tableView.backgroundColor = NWCanvasColor();
    if (NWBluetoothBusy()) {
        self.navigationItem.hidesBackButton = YES; self.navigationController.interactivePopGestureRecognizer.enabled = NO;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NWText(NWBluetoothStopping() ? @"bt.stopping" : @"bt.stop")
            style:UIBarButtonItemStylePlain target:self action:@selector(stop)];
        self.navigationItem.rightBarButtonItem.enabled = !NWBluetoothStopping();
        self.navigationItem.rightBarButtonItem.tintColor = UIColor.systemRedColor;
        self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @"nw.diagnostics.stop";
    } else {
        self.navigationItem.hidesBackButton = NO; self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationItem.rightBarButtonItem = nil;
    }
}
- (void)stop { NWBluetoothStop(); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? 1 : section == 1 ? 5 : section == 2 ? 3 : MIN((NSUInteger)12, self.events.count);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; return NWText(@[@"diag.edition", @"diag.tests", @"diag.report", @"diag.history"][section]);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; return section == 1 ? NWText(@"diag.tests_hint") : section == 2 ? NWText(@"diag.privacy") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table; UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NWStyleCell(cell);
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (index.section == 0) {
        cell.textLabel.text = NW_BUILD_NAME; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", NW_BUILD_VERSION,
            NSBundle.mainBundle.infoDictionary[@"NukeWirelessPackageScheme"] ?: NWText(@"unavailable")]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (index.section == 1) {
        NSArray *keys = @[@"diag.environment", @"diag.wifi", @"diag.ble", @"diag.controller", @"diag.advertising"];
        NSArray *icons = @[@"checkmark.shield", @"wifi", @"dot.radiowaves.left.and.right", @"cpu", @"antenna.radiowaves.left.and.right"];
        cell.textLabel.text = NWText(keys[index.row]); cell.imageView.image = [UIImage systemImageNamed:icons[index.row]];
        cell.accessibilityIdentifier = [@"nw.diagnostics." stringByAppendingString:@[@"environment", @"wifi", @"ble", @"controller", @"advertising"][index.row]];
        cell.detailTextLabel.text = NWText(@[@"diag.environment_hint", @"diag.wifi_hint", @"diag.ble_hint", @"diag.controller_hint", @"diag.advertising_hint"][index.row]);
        BOOL enabled = !NWBluetoothBusy() && !NWScanBusy() && !NWBulkBusy() && !collecting;
        if (!enabled) { cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.textLabel.textColor = UIColor.secondaryLabelColor; cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (index.section == 2) {
        cell.textLabel.text = NWText(@[@"diag.observation", @"diag.export", @"diag.clear"][index.row]);
        cell.imageView.image = [UIImage systemImageNamed:@[@"square.and.pencil", @"square.and.arrow.up", @"trash"][index.row]];
        cell.accessibilityIdentifier = [@"nw.diagnostics." stringByAppendingString:@[@"observation", @"export", @"clear"][index.row]];
        if (NWBluetoothBusy() || self.exporting) { cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.textLabel.textColor = UIColor.secondaryLabelColor; cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled; }
    } else {
        NSDictionary *event = self.events[index.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", event[@"test"], event[@"status"]];
        NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateStyle = NSDateFormatterShortStyle; formatter.timeStyle = NSDateFormatterMediumStyle;
        cell.detailTextLabel.text = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[event[@"time"] doubleValue]]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    // Native list content computes multiline row heights, including long
    // translations and larger accessibility text, with proper vertical margins.
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = cell.textLabel.text; content.secondaryText = cell.detailTextLabel.text;
    content.image = cell.imageView.image;
    content.textProperties.font = cell.textLabel.font; content.textProperties.color = cell.textLabel.textColor;
    content.secondaryTextProperties.font = cell.detailTextLabel.font;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    content.imageProperties.tintColor = NWAccentColor(); cell.contentConfiguration = content;
    return cell;
}
- (void)message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"diag.title") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)exportReport {
    if (self.exporting) return; self.exporting = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil; NSURL *file = NWDiagnosticSaveExport(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.exporting = NO;
            if (!self.view.window || self.presentedViewController || NWBluetoothBusy()) return;
            if (!file) { [self message:NWText(@"diag.save_failed")]; return; }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.tableView;
            share.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)observeResult {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"diag.observation") message:NWText(@"diag.observation_hint") preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *key in @[@"diag.test_name", @"diag.receiver", @"diag.what_happened"])
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = NWText(key); field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"diag.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; NSMutableArray *values = [NSMutableArray new];
        for (UITextField *field in alert.textFields) [values addObject:[(field.text ?: @"") substringToIndex:MIN((NSUInteger)400, field.text.length)]];
        NWDiagnosticRecord(@"tester_observation", @"user_report", @{@"test_name": values[0], @"receiver_model_and_os": values[1], @"observation": values[2]});
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (NWBluetoothBusy()) return;
    if (index.section == 1) {
        if (NWBluetoothBusy() || NWScanBusy() || NWBulkBusy() || collecting) return;
        if (index.row == 0) collectEnvironment();
        else if (index.row == 1) {
            if (!NWRefreshScan()) NWDiagnosticRecord(@"wifi_scan", @"blocked", NWScanDiagnosticSnapshot());
        } else if (index.row == 2) [self.navigationController pushViewController:NWBLEController() animated:YES];
        else if (index.row == 3) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"diag.controller") message:NWText(@"diag.controller_confirm") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:NWText(@"diag.start") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; NWBluetoothStartCapabilityDiagnostic(); }]];
            [self presentViewController:alert animated:YES completion:nil];
        } else [self.navigationController pushViewController:NWBluetoothController() animated:YES];
    } else if (index.section == 2) {
        if (index.row == 0) [self observeResult];
        else if (index.row == 1) [self exportReport];
        else if (!NWBluetoothBusy() && !NWScanBusy() && !NWBulkBusy() && !collecting) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"diag.clear") message:NWText(@"diag.clear_hint") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:NWText(@"diag.clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; NWDiagnosticClear(); }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (index.section == 3 && (NSUInteger)index.row < self.events.count) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:self.events[index.row] options:NSJSONWritingPrettyPrinted error:NULL];
        [self message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    }
}
@end
UIViewController *NWDiagnosticsController(void) { return [NWDiagnosticsViewController new]; }
void NWDiagnosticsInstall(void) {
    NWDiagnosticInitialize();
    struct utsname system = {0}; uname(&system);
    NWDiagnosticRecord(@"application", @"loaded", @{@"build": NW_BUILD_VERSION,
        @"machine": [NSString stringWithUTF8String:system.machine],
        @"ios_version": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"package_scheme": NSBundle.mainBundle.infoDictionary[@"NukeWirelessPackageScheme"] ?: @"unknown",
        @"source_commit": NSBundle.mainBundle.infoDictionary[@"NukeWirelessSourceCommit"] ?: @"unknown"});
    for (NSString *name in @[UIApplicationDidEnterBackgroundNotification, UIApplicationDidBecomeActiveNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NWDiagnosticRecord(@"lifecycle", @"observed", @{@"event": note.name, @"bluetooth_busy": @(NWBluetoothBusy()), @"wifi_busy": @(NWScanBusy())});
        }];
}
#ifdef NW_UI_TESTING
extern int NWBluetoothUIRegressionCatalogState(int state);
int NWDiagnosticsUIRegressionPresent(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) window = candidate;
    UIViewController *root = window.rootViewController;
    if (!root || root.presentedViewController || NWBluetoothBusy()) return 1;
    [root presentViewController:[[UINavigationController alloc] initWithRootViewController:NWDiagnosticsController()] animated:NO completion:nil];
    return 0;
}
int NWDiagnosticsUIRegressionCheck(void) {
    NWDiagnosticsViewController *controller = [NWDiagnosticsViewController new]; [controller loadViewIfNeeded];
    if ([controller numberOfSectionsInTableView:controller.tableView] != 4) return 1;
    UITableViewCell *export = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    if (![export.accessibilityIdentifier isEqual:@"nw.diagnostics.export"]) return 2;
    if (![((UIListContentConfiguration *)export.contentConfiguration).text isEqual:NWText(@"diag.export")]) return 3;
    if (![controller.title isEqual:NWText(@"diag.title")]) return 4;
    NSDictionary *report = NWDiagnosticSnapshot();
    if (![report[@"schema_version"] isEqual:@1] || ![report[@"build"] isEqual:NW_BUILD_VERSION]) return 5;
    NSDictionary *safe = NWDiagnosticRedact(@{@"SSID": @"private-name", @"error": @"target 192.168.1.22 01:02:03:04:05:06"});
    if (![safe[@"SSID"] isEqual:@"[redacted]"] || [safe[@"error"] containsString:@"192.168"]) return 6;
    if ([controller tableView:controller.tableView numberOfRowsInSection:1] != 5) return 7;
    @try {
        NWBluetoothUIRegressionCatalogState(1); [controller refresh];
        if (!controller.navigationItem.hidesBackButton || ![controller.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.diagnostics.stop"] ||
            !controller.navigationItem.rightBarButtonItem.enabled) return 8;
        [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        if (controller.presentedViewController) return 9;
        NWBluetoothUIRegressionCatalogState(2); [controller refresh];
        if (controller.navigationItem.rightBarButtonItem.enabled) return 10;
    } @finally { NWBluetoothUIRegressionCatalogState(0); [controller refresh]; }
    return 0;
}
#endif
