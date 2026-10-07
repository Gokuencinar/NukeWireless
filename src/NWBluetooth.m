#import "NWBluetooth.h"
#import "NWBLE.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import "NWScanBridge.h"
#import "NWMainTabs.h"
#import "NWBluetoothCatalog.h"
#include "NWCatalogProfiles.h"
#include <spawn.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>

NSString *const NWBluetoothChanged = @"NWBluetoothChanged";
static NSString *const reportKey = @"NukeWirelessBluetoothLastReport";
static NSString *const invocationKey = @"NukeWirelessBluetoothLastInvocation";
static BOOL busy, cancelling;
static pid_t worker;
static int workerControl = -1; // Owned/closed by invoke, guarded by workerLock.
static NSObject *workerLock;
static NSDictionary *lastReport;
static BOOL labRunning;
#ifdef NW_UI_TESTING
static BOOL captureCatalogArguments;
static NSArray *capturedCatalogArguments;
#endif
static BOOL labOperation(NSString *operation) {
    return [operation isEqual:@"le_catalog_test"] || [operation isEqual:@"le_swift_pair_test"] || [operation isEqual:@"le_apple_pairing_test"] || [operation isEqual:@"le_fast_pair_test"] || [operation isEqual:@"le_multi_windows_test"] || [operation isEqual:@"le_multi_apple_test"] || [operation isEqual:@"le_multi_android_test"];
}
static BOOL emissionFinishedCleanly(NSDictionary *report) {
    NSString *code = report[@"error_code"];
    return labOperation(report[@"operation"]) && (!code || [code isEqual:@"cancelled"]) &&
        (!report[@"error"] || [code isEqual:@"cancelled"]) && !report[@"cleanup_warning"] &&
        [report[@"controller_advertising_acknowledged"] boolValue] &&
        [report[@"advertising_stopped_acknowledged"] boolValue] &&
        [report[@"advertising_set_removed"] boolValue] && [report[@"service_restored"] boolValue];
}
static BOOL reportVisible(void) { return !busy && lastReport && !emissionFinishedCleanly(lastReport); }
// Assigned by beginBackgroundTask before any worker/completion can read it.
static UIBackgroundTaskIdentifier background;

static void saveInvocation(NSDictionary *details, BOOL cancellable) {
    if (!cancellable) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:details options:0 error:NULL];
    if (data) {
        [NSUserDefaults.standardUserDefaults setObject:data forKey:invocationKey];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
}
static NSString *reportText(NSDictionary *report) {
    NSString *code = report[@"error_code"];
    if ([code isEqual:@"cancelled"] && labOperation(report[@"operation"]) &&
        [report[@"controller_advertising_acknowledged"] boolValue])
        return NWText([report[@"advertising_stopped_acknowledged"] boolValue] &&
            [report[@"advertising_set_removed"] boolValue] && [report[@"service_restored"] boolValue] ?
            @"bt.lab.stopped" : @"bt.lab.stop_unconfirmed");
    if (!code && labOperation(report[@"operation"]))
        return NWText(emissionFinishedCleanly(report) ? @"bt.lab.accepted" : @"bt.lab.incomplete");
    if (!code && [report[@"operation"] isEqual:@"le_capabilities"])
        return NWText([report[@"capabilities_verified"] boolValue] ? @"bt.le.success" : @"bt.le.partial");
    return code ? NWText([@"bt.error." stringByAppendingString:code]) :
        NWText(@"bt.empty");
}

// A support bitmap is a declaration by the controller, not emission evidence.
static NSString *advertisingSupport(NSDictionary *report, BOOL extended) {
    NSString *hex = nil;
    for (NSDictionary *query in report[@"queries"])
        if ([query[@"opcode"] unsignedIntegerValue] == 0x1002 && ![query[@"hci_status"] unsignedIntegerValue])
            hex = query[@"return_data_hex"];
    if (![hex isKindOfClass:NSString.class] || hex.length != 128 ||
        [hex rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet].location != NSNotFound)
        return NWText(@"ble.unavailable");
    const NSUInteger legacy[] = {205, 207, 209}, ext[] = {290, 291, 293};
    const NSUInteger *bits = extended ? ext : legacy;
    for (NSUInteger i = 0; i < 3; ++i) {
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange((bits[i] / 8) * 2, 2)]];
        if (![scanner scanHexInt:&byte]) return NWText(@"ble.unavailable");
        if (!(byte & (1u << (bits[i] % 8)))) return NWText(@"ble.no");
    }
    return NWText(@"ble.yes");
}

static NSString *queryTitle(NSDictionary *query) {
    switch ([query[@"opcode"] unsignedIntegerValue]) {
        case 0x1001: return NWText(@"bt.le.version");
        case 0x1002: return NWText(@"bt.le.commands");
        case 0x1003: return NWText(@"bt.le.features");
        case 0x2003: return NWText(@"bt.le.le_features");
        case 0x201c: return NWText(@"bt.le.states");
        case 0x2036: return NWText(@"bt.lab.parameters");
        case 0x2037: return NWText(@"bt.lab.data");
        case 0x2039: return NWText([query[@"phase"] isEqual:@"disable"] ? @"bt.lab.disable" : @"bt.lab.enable");
        case 0x203c: return NWText(@"bt.lab.remove");
        default: return NWText(@"bt.le.title");
    }
}
static NSArray *reportRows(NSDictionary *report) {
    id rows = report[@"queries"];
    return [rows isKindOfClass:NSArray.class] ? rows : @[];
}

BOOL NWBluetoothBusy(void) { return busy; } // Main-thread UI state.
static NSString *helperPath(void) {
    NSString *app = NSBundle.mainBundle.bundlePath;
    if (![app.lastPathComponent isEqual:@"HarpyReloaded.app"] || ![app.stringByDeletingLastPathComponent.lastPathComponent isEqual:@"Applications"]) return nil;
    NSString *root = app.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    return [root stringByAppendingPathComponent:@"usr/bin/nwbt-run"];
}
// Synchronize reaping with UI cancellation. Once reaped (including by another
// runtime child handler), a PID is never retained as a signal target.
static BOOL childFinished(pid_t child, int *status, BOOL cancellable) {
    @synchronized (workerLock) {
        pid_t waited = waitpid(child, status, WNOHANG);
        BOOL finished = waited == child || (waited < 0 && errno == ECHILD);
        if (finished && cancellable && worker == child) { worker = 0; workerControl = -1; }
        return finished;
    }
}
static void signalChild(pid_t child, int number, BOOL cancellable) {
    @synchronized (workerLock) {
        int status = 0;
        if (!childFinished(child, &status, cancellable)) {
            // Only signal a child still present in our wait set.
            if (waitpid(child, &status, WNOHANG) == 0) {
                if (cancellable && worker == child && workerControl >= 0 && number == SIGTERM) {
                    const char stop = 's'; send(workerControl, &stop, 1, 0);
                } else kill(child, number);
            } else if (cancellable && worker == child) { worker = 0; workerControl = -1; }
        }
    }
}
static void cancelWorker(void) {
    @synchronized (workerLock) { cancelling = YES; if (worker > 0) signalChild(worker, SIGTERM, YES); }
}
static BOOL cancellationRequested(void) {
    @synchronized (workerLock) { return cancelling; }
}
BOOL NWBluetoothStopping(void) { return cancellationRequested(); }
void NWBluetoothStop(void) {
    if (!busy || cancellationRequested()) return;
    cancelWorker();
    [NSNotificationCenter.defaultCenter postNotificationName:NWBluetoothChanged object:nil];
}
NSString *NWBluetoothEmissionIssue(void) {
    return reportVisible() && labOperation(lastReport[@"operation"]) ? reportText(lastReport) : nil;
}

// A separate helper owns privileged operations and recovery. The app only
// supplies argv, reads bounded JSON, and requests cancellation over a private
// inherited socket. The worker's root credentials do not grant the app signals.
static NSDictionary *invoke(NSArray<NSString *> *arguments, BOOL cancellable) {
    saveInvocation(@{@"phase": @"starting"}, cancellable);
    NSString *path = helperPath();
    if (!path || ![NSFileManager.defaultManager isExecutableFileAtPath:path]) return @{@"error_code": @"missing"};
    int out[2], err[2];
    if (pipe(out)) return @{@"error_code": @"transport"};
    if (pipe(err)) { close(out[0]); close(out[1]); return @{@"error_code": @"transport"}; }
    int control[2] = {-1, -1};
    if (cancellable) {
        int enabled = 1;
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, control) ||
            setsockopt(control[1], SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) ||
            fcntl(control[1], F_SETFL, O_NONBLOCK)) {
            if (control[0] >= 0) close(control[0]); if (control[1] >= 0) close(control[1]);
            close(out[0]); close(out[1]); close(err[0]); close(err[1]);
            return @{@"error_code": @"transport"};
        }
    }
    fcntl(out[0], F_SETFL, O_NONBLOCK); fcntl(err[0], F_SETFL, O_NONBLOCK);
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO);
    if (cancellable) posix_spawn_file_actions_adddup2(&actions, control[0], STDIN_FILENO);
    else posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawnattr_t attributes; posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);
    char *argv[6] = {(char *)path.fileSystemRepresentation, NULL, NULL, NULL, NULL, NULL};
    for (NSUInteger i = 0; i < arguments.count && i < 4; ++i) argv[i + 1] = (char *)arguments[i].UTF8String;
    char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", NULL}; pid_t child = 0;
    int launch = posix_spawn(&child, path.fileSystemRepresentation, &actions, &attributes, argv, environment);
    posix_spawnattr_destroy(&attributes); posix_spawn_file_actions_destroy(&actions);
    close(out[1]); close(err[1]);
    if (control[0] >= 0) close(control[0]);
    if (launch) {
        saveInvocation(@{@"phase": @"spawn_failed", @"spawn_errno": @(launch)}, cancellable);
        close(out[0]); close(err[0]); if (control[1] >= 0) close(control[1]);
        return @{@"error_code": @"permissions"};
    }
    if (cancellable) @synchronized (workerLock) {
        worker = child; workerControl = control[1]; if (cancelling) signalChild(child, SIGTERM, YES);
    }
    NSMutableData *data = [NSMutableData new], *diagnostics = [NSMutableData new]; NSUInteger stderrBytes = 0;
    double deadline = NSProcessInfo.processInfo.systemUptime + (cancellable ? 85.0 : 12.0);
    BOOL exited = NO, invalid = NO; int status = 0;
    const NSUInteger maxDataSize = 10 * 1024 * 1024;
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        char buffer[2048]; ssize_t count;
        while ((count = read(out[0], buffer, sizeof(buffer))) > 0) {
            if (data.length + (NSUInteger)count > maxDataSize) { invalid = YES; break; }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        while ((count = read(err[0], buffer, sizeof(buffer))) > 0) {
            if (diagnostics.length < 4096) [diagnostics appendBytes:buffer length:MIN((NSUInteger)count, 4096 - diagnostics.length)];
            stderrBytes += (NSUInteger)count; if (stderrBytes > 65536) { invalid = YES; break; }
        }
        if (invalid) break;
        if (childFinished(child, &status, cancellable)) { exited = YES; break; }
        struct pollfd descriptors[2] = {{out[0], POLLIN, 0}, {err[0], POLLIN, 0}}; poll(descriptors, 2, 25);
    }
    if (!exited) {
        signalChild(child, SIGTERM, cancellable); double cancelDeadline = NSProcessInfo.processInfo.systemUptime + 6.0;
        while (NSProcessInfo.processInfo.systemUptime < cancelDeadline) {
            if (childFinished(child, &status, cancellable)) { exited = YES; break; } usleep(50000);
        }
        if (!exited) { signalChild(child, SIGKILL, cancellable); while (waitpid(child, &status, 0) < 0 && errno == EINTR) {} }
    }
    char buffer[2048]; ssize_t count;
    while ((count = read(out[0], buffer, sizeof(buffer))) > 0 && data.length + (NSUInteger)count <= maxDataSize)
        [data appendBytes:buffer length:(NSUInteger)count];
    close(out[0]); close(err[0]);
    if (cancellable) @synchronized (workerLock) {
        if (worker == child) { worker = 0; workerControl = -1; }
        close(control[1]);
    }
    id report = invalid ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    saveInvocation(@{@"phase": @"finished", @"bytes": @(data.length), @"invalid": @(invalid),
        @"child_exited": @(exited), @"wait_status": @(status),
        @"stderr": [[NSString alloc] initWithData:diagnostics encoding:NSUTF8StringEncoding] ?: @""}, cancellable);
    return [report isKindOfClass:NSDictionary.class] ? report : @{@"error_code": @"transport"};
}

// Stable action identifiers keep presentation groups separate from worker commands.
static NSInteger menuAction(NSIndexPath *index) {
    if (index.section == 0) return index.row == 2 ? 9 : index.row + 1;
    if (index.section >= 1 && index.section <= 3)
        return index.row == 0 ? index.section + 2 : index.section + 5;
    return -1;
}
static UILabel *durationBadge(BOOL enabled) {
    UILabel *badge = [UILabel new];
    badge.text = NWText(@"bt.ui.duration");
    badge.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    badge.adjustsFontForContentSizeCategory = YES;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.textColor = enabled ? NWAccentColor() : UIColor.secondaryLabelColor;
    badge.backgroundColor = [(enabled ? NWAccentColor() : UIColor.secondaryLabelColor) colorWithAlphaComponent:0.10];
    [badge sizeToFit]; badge.frame = CGRectMake(0, 0, badge.bounds.size.width + 20, badge.bounds.size.height + 12);
    badge.layer.cornerRadius = 8; badge.clipsToBounds = YES;
    badge.isAccessibilityElement = NO;
    return badge;
}

@interface NWBluetoothViewController : UITableViewController
@property(nonatomic, strong) NSDictionary *capabilities;
@property(nonatomic) BOOL checking;
- (void)runArguments:(NSArray<NSString *> *)arguments operation:(NSString *)operation;
- (void)stopCurrentOperation;
- (void)emitCatalogPlatform:(NSUInteger)platform models:(NSArray<NSNumber *> *)models;
- (void)finishOperation:(NSDictionary *)report;
@end

@implementation NWBluetoothViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"bt.title");
    if (!lastReport && !busy) {
        NSData *saved = [NSUserDefaults.standardUserDefaults dataForKey:reportKey];
        id report = saved ? [NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL] : nil;
        if ([report isKindOfClass:NSDictionary.class] && (labOperation(report[@"operation"]) || [report[@"operation"] isEqual:@"le_capabilities"])) lastReport = report;
    }
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 64;
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"questionmark.circle"] style:UIBarButtonItemStylePlain
        target:self action:@selector(showHelp)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = NWText(@"bt.ui.help_title");
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier = @"nw.bluetooth.help";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:NWBluetoothChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:NWAppearanceChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!self.isViewLoaded || ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) return;
    // UIKit updates the surrounding native bars during the same trait change.
    // Restyle after that transition so their cached colors match the table.
    dispatch_async(dispatch_get_main_queue(), ^{
        NWStyleNavigationBar(self.navigationController.navigationBar);
        NWStyleMainTabs(self.tabBarController);
        [self refresh:nil];
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar);
    [self refresh:nil];
    if (self.checking || busy) return; self.checking = YES;
    __weak NWBluetoothViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *capabilities = invoke(@[@"--status"], NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            NWBluetoothViewController *controller = weakSelf;
            controller.checking = NO; controller.capabilities = capabilities; [controller refresh:nil];
        });
    });
}
- (void)refresh:(NSNotification *)notification {
    (void)notification; [self.tableView reloadData];
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    self.navigationItem.leftBarButtonItem.tintColor = NWAccentColor();
    self.navigationController.interactivePopGestureRecognizer.enabled = !busy;
    self.navigationItem.hidesBackButton = busy;
    self.navigationItem.leftBarButtonItem.enabled = !busy;
    if (busy) {
        BOOL stopping = cancellationRequested();
        UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithTitle:NWText(stopping ? @"bt.stopping" : @"bt.stop")
            style:UIBarButtonItemStylePlain target:self action:@selector(stopCurrentOperation)];
        stop.enabled = !stopping; stop.tintColor = UIColor.systemRedColor;
        stop.accessibilityIdentifier = @"nw.bluetooth.stop";
        self.navigationItem.rightBarButtonItem = stop;
    } else self.navigationItem.rightBarButtonItem = nil;
}
- (void)showHelp {
    if (self.presentedViewController) return;
    UIAlertController *help = [UIAlertController alertControllerWithTitle:NWText(@"bt.ui.help_title")
        message:NWText(@"bt.ui.help") preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
}
- (void)stopCurrentOperation {
    NWBluetoothStop();
}
- (void)backgrounded:(NSNotification *)notification { (void)notification; [self stopCurrentOperation]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 6; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table;
    if (section <= 3) return section == 0 ? 3 : 2;
    if (section == 4) return busy ? 2 : 0;
    return reportVisible() ? 1 + (labOperation(lastReport[@"operation"]) ? 0 : reportRows(lastReport).count) : 0;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table;
    if (section <= 3) return NWText(@[@"bt.ui.explore", @"bt.ui.windows", @"bt.ui.apple", @"bt.ui.android"][section]);
    if (section == 4) return busy ? NWText(@"bt.ui.active") : nil;
    return reportVisible() ? NWText(labOperation(lastReport[@"operation"]) ? @"bt.ui.attention" : @"bt.ui.last_result") : nil;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;
    if (section == 0) {
        NSString *status = nil;
        if (!self.capabilities) status = NWText(@"bt.checking");
        else if (self.capabilities[@"error_code"]) status = NWText([@"bt.error." stringByAppendingString:self.capabilities[@"error_code"]]);
        else if (![self.capabilities[@"supported"] boolValue]) status = NWText(@"bt.error.unsupported");
        return status ? [NSString stringWithFormat:@"%@\n%@", status, NWText(@"bt.ui.emission_hint")] : NWText(@"bt.ui.emission_hint");
    }
    return nil;
}
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return [self tableView:table numberOfRowsInSection:section] ? UITableViewAutomaticDimension : 0.01;
}
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return [self tableView:table numberOfRowsInSection:section] ? UITableViewAutomaticDimension : 0.01;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table; NSInteger action = menuAction(index); UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (action == 9) {
        content.text = NWText(@"bt.catalog.title"); content.secondaryText = NWText(@"bt.catalog.menu_hint");
        content.image = [UIImage systemImageNamed:@"shuffle"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityIdentifier = @"nw.bluetooth.catalog";
        cell.selectionStyle = busy ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    } else if (action >= 6 && action <= 8) {
        content.text = NWText(@"bt.ui.multiple");
        content.secondaryText = NWText(@[@"bt.ui.windows_multiple", @"bt.ui.apple_multiple", @"bt.ui.android_multiple"][action-6]);
        content.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.selectionStyle = !busy && [self.capabilities[@"supported"] boolValue] &&
            [self.capabilities[@"supports_le_multi_device_test"] boolValue] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = NWAccentColor();
    } else if (action == 5) {
        content.text = NWText(@"bt.ui.single");
        content.secondaryText = NWText(@"bt.ui.android_single");
        content.image = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
        cell.selectionStyle = !busy && [self.capabilities[@"supported"] boolValue] &&
            [self.capabilities[@"supports_le_fast_pair_test"] boolValue] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = NWAccentColor();
    } else if (action == 4) {
        content.text = NWText(@"bt.ui.single");
        content.secondaryText = NWText(@"bt.ui.apple_single");
        content.image = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
        cell.selectionStyle = !busy && [self.capabilities[@"supported"] boolValue] &&
            [self.capabilities[@"supports_le_apple_pairing_test"] boolValue] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = NWAccentColor();
    } else if (action == 3) {
        content.text = NWText(@"bt.ui.single");
        content.secondaryText = NWText(@"bt.ui.swift_single");
        content.image = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
        cell.selectionStyle = !busy && [self.capabilities[@"supported"] boolValue] &&
            [self.capabilities[@"supports_le_swift_pair_test"] boolValue] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = NWAccentColor();
    } else if (action == 2) {
        content.text = NWText(@"bt.ui.capabilities");
        content.secondaryText = NWText(@"bt.ui.capabilities_hint");
        content.image = [UIImage systemImageNamed:@"cpu"];
        cell.selectionStyle = !busy && [self.capabilities[@"supported"] boolValue] &&
            [self.capabilities[@"supports_le_capability_app"] boolValue] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = NWAccentColor();
    } else if (action == 1) {
        content.text = NWText(@"ble.title"); content.secondaryText = NWText(@"bt.ui.scan_hint");
        content.image = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = busy ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    } else if (index.section == 4) {
        BOOL stopping = busy && cancellationRequested();
        content.text = index.row || busy ? NWText(index.row ? (stopping ? @"bt.stopping" : labRunning ? @"bt.lab.stop" : @"bt.cancel") :
            stopping ? @"bt.stopping" : labRunning ? @"bt.lab.running" : @"bt.le.running") : NWText(@"bt.empty");
        content.image = [UIImage systemImageNamed:index.row ? @"stop.circle" : @"waveform.path"];
        cell.selectionStyle = index.row && busy && !stopping ?
            UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = index.row ? UIColor.systemRedColor : NWAccentColor();
    } else if (!lastReport) content.text = NWText(@"bt.empty");
    else if (index.row == 0) {
        NSString *code = lastReport[@"error_code"];
        content.text = reportText(lastReport);
        NSMutableArray<NSString *> *details = [NSMutableArray new];
        if ([lastReport[@"operation"] isEqual:@"le_capabilities"]) {
            [details addObject:[NSString stringWithFormat:NWText(@"bt.le.support"),
                advertisingSupport(lastReport, NO), advertisingSupport(lastReport, YES)]];
            [details addObject:NWText(@"bt.le.read_only")];
        }
        if ([lastReport[@"operation"] isEqual:@"le_swift_pair_test"]) [details addObject:NWText(@"bt.lab.swift_receiver")];
        if ([lastReport[@"operation"] isEqual:@"le_fast_pair_test"]) [details addObject:NWText(@"bt.lab.android_receiver")];
        if ([lastReport[@"operation"] isEqual:@"le_apple_pairing_test"]) [details addObject:NWText(@"bt.lab.apple_receiver")];
        if ([lastReport[@"operation"] isEqual:@"le_catalog_test"] && [lastReport[@"models"] isKindOfClass:NSArray.class])
            [details addObject:[lastReport[@"models"] componentsJoinedByString:@", "]];
        if ([lastReport[@"service_restored"] boolValue]) [details addObject:NWText(@"bt.restored")];
        content.secondaryText = [details componentsJoinedByString:@"\n"];
        content.image = [UIImage systemImageNamed:code ? @"exclamationmark.circle" : @"checkmark.circle"];
    } else if (lastReport[@"operation"]) {
        NSDictionary *query = lastReport[@"queries"][index.row - 1];
        content.text = queryTitle(query);
        BOOL success = (query[@"return_data_hex"] || [query[@"acknowledged"] boolValue]) &&
            query[@"hci_status"] && ![query[@"hci_status"] unsignedIntegerValue];
        content.secondaryText = success ? NWText(@"bt.le.reply") : query[@"hci_status"] ?
            [NSString stringWithFormat:NWText(@"bt.le.rejected"), [query[@"hci_status"] unsignedIntegerValue]] : NWText(@"bt.timeout");
        content.image = [UIImage systemImageNamed:success ? @"checkmark.circle" : @"exclamationmark.circle"];
    }
    UIColor *tint = NWAccentColor();
    if (action >= 1) {
        BOOL enabled = cell.selectionStyle != UITableViewCellSelectionStyleNone;
        content.textProperties.color = enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        tint = enabled ? NWAccentColor() : UIColor.tertiaryLabelColor;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
        if (!enabled) cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
        if (action >= 3 && action <= 8) {
            content.image = [UIImage systemImageNamed:action >= 6 ? @"square.stack.3d.up" : @"play.circle.fill"];
            cell.accessoryView = durationBadge(enabled);
            NSString *platform = NWText(@[@"bt.ui.windows", @"bt.ui.apple", @"bt.ui.android"][index.section-1]);
            cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@", platform,
                content.text, content.secondaryText, NWText(@"bt.ui.duration")];
        }
    } else if (index.section == 4 && index.row == 0) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = NWAccentColor(); [spinner startAnimating]; cell.accessoryView = spinner;
    }
    if (index.section == 4 && index.row == 1) tint = UIColor.systemRedColor;
    content.imageProperties.tintColor = tint; cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    NSInteger action = menuAction(index);
    if (action == 9) {
        if (!busy) {
            BOOL available = [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_catalog_identity_v2"] boolValue];
            __weak NWBluetoothViewController *weakSelf = self;
            UIViewController *catalog = NWBluetoothCatalogControllerWithEmitter(available, ^(NSUInteger platform, NSArray<NSNumber *> *models) {
                [weakSelf emitCatalogPlatform:platform models:models];
            });
            [self.navigationController pushViewController:catalog animated:YES];
        }
        return;
    }
    if (action == 1 && !busy) {
        [self.navigationController pushViewController:NWBLEController() animated:YES]; return;
    }
    if (action == 2) {
        if (!busy && [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_capability_app"] boolValue])
            [self runArguments:@[@"--le-capabilities"] operation:@"le_capabilities"];
        return;
    }
    if (action == 3) {
        if (!busy && [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_swift_pair_test"] boolValue])
            [self runArguments:@[@"--le-swift-pair-test"] operation:@"le_swift_pair_test"];
        return;
    }
    if (action == 4) {
        if (!busy && [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_apple_pairing_test"] boolValue])
            [self runArguments:@[@"--le-apple-pairing-test"] operation:@"le_apple_pairing_test"];
        return;
    }
    if (action == 5) {
        if (!busy && [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_fast_pair_test"] boolValue])
            [self runArguments:@[@"--le-fast-pair-test"] operation:@"le_fast_pair_test"];
        return;
    }
    if (action >= 6 && action <= 8) {
        if (!busy && [self.capabilities[@"supported"] boolValue] && [self.capabilities[@"supports_le_multi_device_test"] boolValue])
            [self runArguments:@[@[@"--le-multi-windows-test", @"--le-multi-apple-test", @"--le-multi-android-test"][action-6]]
                operation:@[@"le_multi_windows_test", @"le_multi_apple_test", @"le_multi_android_test"][action-6]];
        return;
    }
    if (index.section == 4 && index.row == 1) [self stopCurrentOperation];
}
- (void)emitCatalogPlatform:(NSUInteger)platform models:(NSArray<NSNumber *> *)models {
    if (busy || NWBulkBusy() || ![self.capabilities[@"supported"] boolValue] ||
        ![self.capabilities[@"supports_le_catalog_identity_v2"] boolValue] || platform >= NW_CATALOG_PLATFORMS ||
        models.count < 1 || models.count > NW_CATALOG_SELECTION) return;
    unsigned selected[3]; NSMutableArray *indices = [NSMutableArray new];
    for (NSUInteger i = 0; i < models.count; ++i) {
        if (models[i].unsignedIntegerValue >= NW_CATALOG_MODELS) return;
        selected[i] = models[i].unsignedIntValue; [indices addObject:models[i].stringValue];
    }
    if (!NWCatalogProfileSelection((unsigned)platform, selected, models.count)) return;
    [self runArguments:@[@"--le-catalog-test", [NSString stringWithFormat:@"%lu", (unsigned long)platform],
        [indices componentsJoinedByString:@","]] operation:@"le_catalog_test"];
}
- (void)runArguments:(NSArray<NSString *> *)arguments operation:(NSString *)operation {
    if (busy || NWBulkBusy()) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bt.error.busy") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (!workerLock) workerLock = [NSObject new];
    @synchronized (workerLock) { cancelling = NO; worker = 0; }
    labRunning = labOperation(operation);
    [self.view endEditing:YES];
    busy = YES; lastReport = nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:reportKey];
    background = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"NukeWirelessBluetoothCleanup" expirationHandler:^{ [self stopCurrentOperation]; }];
    [NSNotificationCenter.defaultCenter postNotificationName:NWBluetoothChanged object:nil];
    [self refresh:nil];
#ifdef NW_UI_TESTING
    if (captureCatalogArguments && [operation isEqual:@"le_catalog_test"]) { capturedCatalogArguments = [arguments copy]; return; }
#endif
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary *report = [invoke(arguments, YES) mutableCopy];
        if (operation) report[@"operation"] = operation;
        NSData *saved = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
        if (saved) {
            [NSUserDefaults.standardUserDefaults setObject:saved forKey:reportKey];
            [NSUserDefaults.standardUserDefaults synchronize];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishOperation:report];
        });
    });
}
- (void)finishOperation:(NSDictionary *)report {
    lastReport = report; busy = NO;
    if (background != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:background]; background = UIBackgroundTaskInvalid; }
    [NSNotificationCenter.defaultCenter postNotificationName:NWBluetoothChanged object:nil];
    [self refresh:nil];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"bt.finished"));
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated]; self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}
@end

UIViewController *NWBluetoothController(void) { return [NWBluetoothViewController new]; }

#ifdef NW_UI_TESTING
int NWBluetoothUIRegressionCatalogState(int state) {
    if (state < 0 || state > 3) return 1;
    if (!workerLock) workerLock = [NSObject new];
    busy = state == 1 || state == 2; labRunning = YES;
    @synchronized (workerLock) { cancelling = state == 2; }
    lastReport = state == 3 ? @{@"operation": @"le_catalog_test", @"error_code": @"recovery", @"service_restored": @NO} : nil;
    [NSNotificationCenter.defaultCenter postNotificationName:NWBluetoothChanged object:nil];
    return 0;
}
int NWBluetoothUIRegressionCheck(void) {
    NSDictionary *previous = lastReport; BOOL previousBusy = busy, previousLab = labRunning;
    if (!workerLock) workerLock = [NSObject new];
    BOOL previousCancelling = cancellationRequested();
    NWBeginWiFiScanUITest();
    @try {
        @synchronized (workerLock) { cancelling = NO; }
        busy = NO;
        NSMutableString *bitmap = [NSMutableString new];
        for (NSUInteger i = 0; i < 64; ++i) [bitmap appendString:@"ff"];
        NSDictionary *commands = @{@"opcode": @0x1002, @"hci_status": @0, @"return_data_hex": bitmap};
        lastReport = @{@"operation": @"le_capabilities", @"capabilities_verified": @YES,
                       @"queries": @[commands], @"service_restored": @YES};
        if (![advertisingSupport(lastReport, NO) isEqual:NWText(@"ble.yes")] ||
            ![advertisingSupport(lastReport, YES) isEqual:NWText(@"ble.yes")]) return 1;
        if (![advertisingSupport(@{@"queries": @[@{@"opcode": @0x1002, @"hci_status": @0,
              @"return_data_hex": @"00"}]}, NO) isEqual:NWText(@"ble.unavailable")]) return 2;
        NWBluetoothViewController *controller = [NWBluetoothViewController new];
        [controller loadViewIfNeeded];
        if ([controller numberOfSectionsInTableView:controller.tableView] != 6 ||
            [controller tableView:controller.tableView numberOfRowsInSection:4] != 0 ||
            [controller tableView:controller.tableView numberOfRowsInSection:0] != 3) return 42;
        NSIndexPath *catalog = [NSIndexPath indexPathForRow:2 inSection:0];
        UITableViewCell *catalogCell = [controller tableView:controller.tableView cellForRowAtIndexPath:catalog];
        if (catalogCell.selectionStyle != UITableViewCellSelectionStyleDefault || catalogCell.accessoryView ||
            ![((UIListContentConfiguration *)catalogCell.contentConfiguration).text isEqual:NWText(@"bt.catalog.title")]) return 46;
        if (NWBluetoothCatalogUIRegressionCheck()) return 47;
        for (NSInteger section=1; section<=3; section++) {
            if ([controller tableView:controller.tableView numberOfRowsInSection:section] != 2) return 43;
            for (NSInteger row=0; row<2; row++) {
                UITableViewCell *retained = [controller tableView:controller.tableView cellForRowAtIndexPath:
                    [NSIndexPath indexPathForRow:row inSection:section]];
                if (![((UIListContentConfiguration *)retained.contentConfiguration).text isEqual:NWText(row ? @"bt.ui.multiple" : @"bt.ui.single")]) return 43;
                if (![retained.accessoryView isKindOfClass:UILabel.class] || ![retained.accessibilityLabel containsString:NWText(@"bt.ui.duration")]) return 44;
            }
        }
        if (controller.navigationItem.leftBarButtonItem.action != @selector(showHelp)) return 45;
        controller.capabilities = @{@"supported": @YES, @"supports_le_capability_reads": @YES};
        NSIndexPath *button = [NSIndexPath indexPathForRow:1 inSection:0];
        UITableViewCell *cell = [controller tableView:controller.tableView cellForRowAtIndexPath:button];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 3;
        controller.capabilities = @{@"supported": @YES, @"supports_le_capability_app": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:button];
        if (cell.selectionStyle != UITableViewCellSelectionStyleDefault) return 4;
        if ([controller tableView:controller.tableView numberOfRowsInSection:5] != 2) return 5;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:5]];
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.text isEqual:NWText(@"bt.le.success")] || ![content.secondaryText containsString:NWText(@"bt.restored")]) return 6;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:5]];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.text isEqual:NWText(@"bt.le.commands")] || ![content.secondaryText isEqual:NWText(@"bt.le.reply")]) return 7;
        busy = YES; labRunning = NO;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:button];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone ||
            [controller tableView:controller.tableView numberOfRowsInSection:4] != 2) return 8;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.text isEqual:NWText(@"bt.le.running")]) return 9;
        busy = NO;
        lastReport = @{@"operation": @"le_swift_pair_test", @"controller_advertising_acknowledged": @YES,
            @"advertising_stopped_acknowledged": @YES, @"queries": @[@{@"opcode": @0x2039,
            @"phase": @"disable", @"hci_status": @0, @"acknowledged": @YES}], @"advertising_set_removed": @YES, @"service_restored": @YES};
        if (![reportText(lastReport) isEqual:NWText(@"bt.lab.accepted")] || reportVisible() ||
            [controller tableView:controller.tableView numberOfRowsInSection:5] || NWBluetoothEmissionIssue()) return 10;
        NSMutableDictionary *failedCleanup = [lastReport mutableCopy]; failedCleanup[@"service_restored"] = @NO;
        lastReport = failedCleanup;
        if (!reportVisible() || [controller tableView:controller.tableView numberOfRowsInSection:5] != 1 ||
            ![NWBluetoothEmissionIssue() isEqual:NWText(@"bt.lab.incomplete")]) return 11;
        NSIndexPath *swiftButton = [NSIndexPath indexPathForRow:0 inSection:1];
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:swiftButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 20;
        controller.capabilities = @{@"supported": @YES, @"supports_le_swift_pair_test": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:swiftButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleDefault || !labOperation(@"le_swift_pair_test")) return 21;
        lastReport = @{@"operation": @"le_swift_pair_test", @"controller_advertising_acknowledged": @YES,
            @"advertising_stopped_acknowledged": @YES, @"service_restored": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:5]];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.secondaryText containsString:NWText(@"bt.lab.swift_receiver")]) return 22;
        busy = YES;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:swiftButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 23;
        labRunning = YES;
        [controller refresh:nil];
        UIBarButtonItem *stop = controller.navigationItem.rightBarButtonItem;
        if (!stop.enabled || ![stop.title isEqual:NWText(@"bt.stop")] || stop.action != @selector(stopCurrentOperation)) return 24;
        // Cancellation before spawn must remain latched for the future worker.
        [controller stopCurrentOperation];
        stop = controller.navigationItem.rightBarButtonItem;
        if (!cancellationRequested() || stop.enabled || ![stop.title isEqual:NWText(@"bt.stopping")]) return 25;
        NSIndexPath *cancelButton = [NSIndexPath indexPathForRow:1 inSection:4];
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:cancelButton];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone || ![content.text isEqual:NWText(@"bt.stopping")]) return 26;
        [controller stopCurrentOperation]; // A repeated tap cannot restart or re-enable anything.
        busy = NO; [controller refresh:nil];
        if (controller.navigationItem.rightBarButtonItem) return 27;
        lastReport = @{@"operation": @"le_swift_pair_test", @"error_code": @"cancelled",
            @"controller_advertising_acknowledged": @YES, @"advertising_stopped_acknowledged": @YES,
            @"advertising_set_removed": @YES, @"service_restored": @YES};
        if (![reportText(lastReport) isEqual:NWText(@"bt.lab.stopped")]) return 28;
        NSMutableDictionary *incomplete = [lastReport mutableCopy];
        incomplete[@"advertising_stopped_acknowledged"] = @NO;
        if (![reportText(incomplete) isEqual:NWText(@"bt.lab.stop_unconfirmed")]) return 29;
        incomplete[@"advertising_stopped_acknowledged"] = @YES; incomplete[@"service_restored"] = @NO;
        if (![reportText(incomplete) isEqual:NWText(@"bt.lab.stop_unconfirmed")]) return 30;
        NSIndexPath *appleButton = [NSIndexPath indexPathForRow:0 inSection:2];
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:appleButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 31;
        controller.capabilities = @{@"supported": @YES, @"supports_le_apple_pairing_test": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:appleButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleDefault || !labOperation(@"le_apple_pairing_test")) return 32;
        lastReport = @{@"operation": @"le_apple_pairing_test", @"controller_advertising_acknowledged": @YES,
            @"advertising_stopped_acknowledged": @YES, @"service_restored": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:5]];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.secondaryText containsString:NWText(@"bt.lab.apple_receiver")]) return 33;
        busy = YES;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:appleButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 34;
        busy = NO; controller.capabilities = @{};
        NSIndexPath *androidButton = [NSIndexPath indexPathForRow:0 inSection:3];
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:androidButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 35;
        controller.capabilities = @{@"supported": @YES, @"supports_le_fast_pair_test": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:androidButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleDefault || !labOperation(@"le_fast_pair_test")) return 36;
        lastReport = @{@"operation": @"le_fast_pair_test", @"controller_advertising_acknowledged": @YES,
            @"advertising_stopped_acknowledged": @YES, @"service_restored": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:5]];
        content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content.secondaryText containsString:NWText(@"bt.lab.android_receiver")]) return 37;
        busy = YES;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:androidButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 38;
        busy = NO; controller.capabilities = @{};
        NSIndexPath *sequenceButton = [NSIndexPath indexPathForRow:1 inSection:1];
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:sequenceButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 39;
        controller.capabilities = @{@"supported": @YES, @"supports_le_multi_device_test": @YES};
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:sequenceButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleDefault || !labOperation(@"le_multi_windows_test") || !NWScanBusy()) return 40;
        busy = YES;
        cell = [controller tableView:controller.tableView cellForRowAtIndexPath:sequenceButton];
        if (cell.selectionStyle != UITableViewCellSelectionStyleNone) return 41;
        busy = NO; capturedCatalogArguments = nil; captureCatalogArguments = YES;
        controller.capabilities = @{@"supported": @YES, @"supports_le_catalog_test": @YES, @"supports_le_catalog_identity_v2": @YES};
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
        UIViewController *catalogScreen = navigation.topViewController;
        if (catalogScreen == controller) return 45;
        [catalogScreen setValue:@2 forKey:@"platform"];
        [catalogScreen setValue:@[
            @{@"model": @5, @"name": @"Xbox Wireless Controller", @"identity": @"NWLab-12345678"},
            @{@"model": @1, @"name": @"Surface Mouse", @"identity": @"NWLab-23456789"},
            @{@"model": @4, @"name": @"Surface Headphones 2", @"identity": @"NWLab-34567890"}] forKey:@"models"];
        [(UITableViewController *)catalogScreen tableView:((UITableViewController *)catalogScreen).tableView
            didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
        if (navigation.topViewController != catalogScreen || !busy ||
            ![capturedCatalogArguments isEqual:@[@"--le-catalog-test", @"2", @"5,1,4"]] || !labOperation(@"le_catalog_test")) return 46;
        [(UITableViewController *)catalogScreen loadViewIfNeeded];
        if (!catalogScreen.navigationItem.rightBarButtonItem.enabled ||
            ![catalogScreen.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.catalog.stop"] ||
            !catalogScreen.navigationItem.hidesBackButton || navigation.interactivePopGestureRecognizer.enabled) return 53;
        UITableViewController *catalogTable = (UITableViewController *)catalogScreen;
        NSIndexPath *emitButton = [NSIndexPath indexPathForRow:2 inSection:0];
        UITableViewCell *emitCell = [catalogTable tableView:catalogTable.tableView cellForRowAtIndexPath:emitButton];
        if (![ ((UIListContentConfiguration *)emitCell.contentConfiguration).text isEqual:NWText(@"bt.stop")]) return 54;
        NSArray *selectionBefore = [[catalogScreen valueForKey:@"models"] copy];
        [catalogTable tableView:catalogTable.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        if (![selectionBefore isEqual:[catalogScreen valueForKey:@"models"]]) return 55;
        [catalogTable tableView:catalogTable.tableView didSelectRowAtIndexPath:emitButton];
        if (!cancellationRequested() || catalogScreen.navigationItem.rightBarButtonItem.enabled ||
            ![catalogScreen.navigationItem.rightBarButtonItem.title isEqual:NWText(@"bt.stopping")]) return 56;
        NSDictionary *quiet = @{@"operation": @"le_catalog_test", @"error_code": @"cancelled",
            @"controller_advertising_acknowledged": @YES, @"advertising_stopped_acknowledged": @YES,
            @"advertising_set_removed": @YES, @"service_restored": @YES};
        [controller finishOperation:quiet];
        if (navigation.topViewController != catalogScreen || busy || NWBluetoothEmissionIssue() ||
            [catalogTable numberOfSectionsInTableView:catalogTable.tableView] != 2 ||
            catalogScreen.navigationItem.hidesBackButton || !navigation.interactivePopGestureRecognizer.enabled ||
            ![catalogScreen.navigationItem.rightBarButtonItem.accessibilityIdentifier isEqual:@"nw.catalog.help"]) return 57;
        NSMutableDictionary *restoreFailure = [quiet mutableCopy]; restoreFailure[@"service_restored"] = @NO;
        [controller finishOperation:restoreFailure];
        if (navigation.topViewController != catalogScreen || !NWBluetoothEmissionIssue() ||
            [catalogTable numberOfSectionsInTableView:catalogTable.tableView] != 3) return 58;
        [controller finishOperation:quiet];
        capturedCatalogArguments = nil; busy = YES;
        [controller emitCatalogPlatform:0 models:@[@0]];
        if (capturedCatalogArguments) return 47;
        busy = NO; controller.capabilities = @{@"supported": @YES};
        [controller emitCatalogPlatform:0 models:@[@0]];
        if (capturedCatalogArguments) return 48;
        controller.capabilities = @{@"supported": @YES, @"supports_le_catalog_test": @YES, @"supports_le_catalog_identity_v2": @YES};
        [controller emitCatalogPlatform:1 models:@[@3]];
        if (capturedCatalogArguments) return 49;
        controller.capabilities = @{@"supported": @YES, @"supports_le_catalog_test": @YES};
        [controller emitCatalogPlatform:0 models:@[@0]];
        if (capturedCatalogArguments) return 51; // app27 must not use the corrected identity table.
        controller.capabilities = @{@"supported": @YES, @"supports_le_catalog_identity_v2": @YES};
        [controller emitCatalogPlatform:3 models:@[@5, @2, @0]];
        if (![capturedCatalogArguments isEqual:@[@"--le-catalog-test", @"3", @"5,2,0"]]) return 52;
        [controller finishOperation:quiet];
        lastReport = @{@"operation": @"le_catalog_test", @"error_code": @"cancelled",
            @"controller_advertising_acknowledged": @YES, @"advertising_stopped_acknowledged": @YES,
            @"advertising_set_removed": @YES, @"service_restored": @YES};
        if (![reportText(lastReport) isEqual:NWText(@"bt.lab.stopped")]) return 50;
        for (NSString *operation in @[@"le_catalog_test", @"le_swift_pair_test", @"le_apple_pairing_test", @"le_fast_pair_test",
            @"le_multi_windows_test", @"le_multi_apple_test", @"le_multi_android_test"]) {
            NSMutableDictionary *complete = [quiet mutableCopy]; complete[@"operation"] = operation;
            [complete removeObjectForKey:@"error_code"]; lastReport = complete;
            if (reportVisible() || !emissionFinishedCleanly(complete)) return 59;
            for (NSString *field in @[@"controller_advertising_acknowledged", @"advertising_stopped_acknowledged", @"advertising_set_removed", @"service_restored"]) {
                NSMutableDictionary *partial = [complete mutableCopy]; partial[field] = @NO; lastReport = partial;
                if (!reportVisible() || !NWBluetoothEmissionIssue()) return 60;
            }
            complete[@"cleanup_warning"] = @"fixture"; lastReport = complete;
            if (!reportVisible()) return 61;
        }
        return 0;
    } @finally {
        if (background != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:background]; background = UIBackgroundTaskInvalid; }
        NWEndWiFiScanUITest();
        lastReport = previous; busy = previousBusy; labRunning = previousLab;
        @synchronized (workerLock) { cancelling = previousCancelling; }
        captureCatalogArguments = NO; capturedCatalogArguments = nil;
    }
}
#endif
