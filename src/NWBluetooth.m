#import "NWBluetooth.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import "NWScanBridge.h"
#import "NWBluetoothLimits.h"
#include <spawn.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

static NSString *const changed = @"NWBluetoothChanged";
static NSString *const reportKey = @"NukeWirelessBluetoothLastReport";
static NSString *const invocationKey = @"NukeWirelessBluetoothLastInvocation";
static NSString *const countKey = @"NukeWirelessBluetoothPingCount";
static NSString *const intervalKey = @"NukeWirelessBluetoothPingIntervalMS";
static BOOL busy, cancelling;
static pid_t worker;
static NSObject *workerLock;
static NSDictionary *lastReport;
// Assigned by beginBackgroundTask before any worker/completion can read it.
static UIBackgroundTaskIdentifier background;

static BOOL numericValue(NSString *text, NSUInteger *result) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length || value.length > 4) return NO;
    NSUInteger number = 0;
    for (NSUInteger i = 0; i < value.length; ++i) {
        unichar digit = [value characterAtIndex:i];
        if (digit < '0' || digit > '9') return NO;
        number = number * 10 + (NSUInteger)(digit - '0');
    }
    *result = number; return YES;
}

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
    return code ? NWText([@"bt.error." stringByAppendingString:code]) :
        [NSString stringWithFormat:NWText(@"bt.summary"), [report[@"echo_replies_verified"] unsignedIntegerValue],
            [report[@"echo_requests_submitted"] unsignedIntegerValue]];
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
        if (finished && cancellable && worker == child) worker = 0;
        return finished;
    }
}
static void signalChild(pid_t child, int number, BOOL cancellable) {
    @synchronized (workerLock) {
        int status = 0;
        if (!childFinished(child, &status, cancellable)) {
            // Only signal a child still present in our wait set.
            if (waitpid(child, &status, WNOHANG) == 0) kill(child, number);
            else if (cancellable && worker == child) worker = 0;
        }
    }
}
static void cancelWorker(void) {
    @synchronized (workerLock) { cancelling = YES; if (worker > 0) signalChild(worker, SIGTERM, YES); }
}

// A separate helper owns privileged operations and recovery. The app only
// supplies argv, reads bounded JSON, and signals that worker when cancelled.
static NSDictionary *invoke(NSArray<NSString *> *arguments, BOOL cancellable) {
    saveInvocation(@{@"phase": @"starting"}, cancellable);
    NSString *path = helperPath();
    if (!path || ![NSFileManager.defaultManager isExecutableFileAtPath:path]) return @{@"error_code": @"missing"};
    int out[2], err[2];
    if (pipe(out)) return @{@"error_code": @"transport"};
    if (pipe(err)) { close(out[0]); close(out[1]); return @{@"error_code": @"transport"}; }
    fcntl(out[0], F_SETFL, O_NONBLOCK); fcntl(err[0], F_SETFL, O_NONBLOCK);
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawnattr_t attributes; posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);
    char *argv[6] = {(char *)path.fileSystemRepresentation, NULL, NULL, NULL, NULL, NULL};
    for (NSUInteger i = 0; i < arguments.count && i < 4; ++i) argv[i + 1] = (char *)arguments[i].UTF8String;
    char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", NULL}; pid_t child = 0;
    int launch = posix_spawn(&child, path.fileSystemRepresentation, &actions, &attributes, argv, environment);
    posix_spawnattr_destroy(&attributes); posix_spawn_file_actions_destroy(&actions);
    close(out[1]); close(err[1]);
    if (launch) {
        saveInvocation(@{@"phase": @"spawn_failed", @"spawn_errno": @(launch)}, cancellable);
        close(out[0]); close(err[0]); return @{@"error_code": @"permissions"};
    }
    if (cancellable) @synchronized (workerLock) { worker = child; if (cancelling) signalChild(child, SIGTERM, YES); }
    NSMutableData *data = [NSMutableData new], *diagnostics = [NSMutableData new]; NSUInteger stderrBytes = 0;
    double deadline = NSProcessInfo.processInfo.systemUptime + (cancellable ? 85.0 : 12.0);
    BOOL exited = NO, invalid = NO; int status = 0;
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        char buffer[2048]; ssize_t count;
        while ((count = read(out[0], buffer, sizeof(buffer))) > 0) {
            if (data.length + (NSUInteger)count > 65536) { invalid = YES; break; }
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
    while ((count = read(out[0], buffer, sizeof(buffer))) > 0 && data.length + (NSUInteger)count <= 65536)
        [data appendBytes:buffer length:(NSUInteger)count];
    close(out[0]); close(err[0]);
    if (cancellable) @synchronized (workerLock) { if (worker == child) worker = 0; }
    id report = invalid ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    saveInvocation(@{@"phase": @"finished", @"bytes": @(data.length), @"invalid": @(invalid),
        @"child_exited": @(exited), @"wait_status": @(status),
        @"stderr": [[NSString alloc] initWithData:diagnostics encoding:NSUTF8StringEncoding] ?: @""}, cancellable);
    return [report isKindOfClass:NSDictionary.class] ? report : @{@"error_code": @"transport"};
}

@interface NWBluetoothViewController : UITableViewController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField *address;
@property(nonatomic, strong) UITextField *countField, *intervalField;
@property(nonatomic, strong) NSDictionary *capabilities;
@property(nonatomic) BOOL checking;
@property(nonatomic) NSUInteger pingCount, intervalMS;
@end

@implementation NWBluetoothViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (UITextField *)numericField:(NSString *)label value:(NSUInteger)value {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 90, 44)];
    field.keyboardType = UIKeyboardTypeNumberPad; field.delegate = self;
    field.textAlignment = NSTextAlignmentRight; field.textColor = NWAccentColor();
    field.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightMedium];
    field.text = [NSString stringWithFormat:@"%lu", value]; field.accessibilityLabel = label;
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    toolbar.tintColor = NWAccentColor();
    toolbar.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:NWText(@"bt.done") style:UIBarButtonItemStyleDone target:self action:@selector(finishEditing)]];
    field.inputAccessoryView = toolbar; return field;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"bt.title");
    if (!lastReport && !busy) {
        NSData *saved = [NSUserDefaults.standardUserDefaults dataForKey:reportKey];
        id report = saved ? [NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL] : nil;
        if ([report isKindOfClass:NSDictionary.class]) lastReport = report;
    }
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 65;
    self.tableView.backgroundColor = NWCanvasColor(); self.tableView.tintColor = NWAccentColor();
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.address = [UITextField new]; self.address.placeholder = @"AA:BB:CC:DD:EE:FF";
    self.address.keyboardType = UIKeyboardTypeASCIICapable; self.address.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.address.autocorrectionType = UITextAutocorrectionTypeNo; self.address.spellCheckingType = UITextSpellCheckingTypeNo;
    self.address.returnKeyType = UIReturnKeyDone; self.address.delegate = self;
    self.address.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular];
    self.address.accessibilityLabel = NWText(@"bt.address"); self.address.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.address.text = [NSUserDefaults.standardUserDefaults stringForKey:@"NukeWirelessBluetoothTarget"];
    NSUInteger savedCount = [NSUserDefaults.standardUserDefaults integerForKey:countKey];
    NSUInteger savedInterval = [NSUserDefaults.standardUserDefaults integerForKey:intervalKey];
    // Migrate only the former seconds preference, never reinterpret new values.
    if (![NSUserDefaults.standardUserDefaults objectForKey:intervalKey]) {
        NSUInteger seconds = [NSUserDefaults.standardUserDefaults integerForKey:@"NukeWirelessBluetoothPingInterval"];
        if (NWBTPingOptionsValid(savedCount, seconds)) savedInterval = seconds * 1000;
    }
    BOOL valid = NWBTPingMillisecondsValid(savedCount, savedInterval);
    self.pingCount = valid ? savedCount : NWBT_DEFAULT_COUNT;
    self.intervalMS = valid ? savedInterval : NWBT_DEFAULT_INTERVAL_MS;
    self.countField = [self numericField:NWText(@"bt.count") value:self.pingCount];
    self.intervalField = [self numericField:NWText(@"bt.interval_ms") value:self.intervalMS];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh:) name:changed object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
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
    (void)notification; self.address.enabled = !busy;
    self.countField.enabled = !busy; self.intervalField.enabled = !busy;
    // Passive capability refresh must not dismiss the active keyboard.
    if (!busy && (self.address.isFirstResponder || self.countField.isFirstResponder || self.intervalField.isFirstResponder))
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    else [self.tableView reloadData];
    self.navigationController.interactivePopGestureRecognizer.enabled = !busy;
    self.navigationItem.hidesBackButton = busy;
}
- (void)backgrounded:(NSNotification *)notification { (void)notification; if (busy) cancelWorker(); }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)finishEditing { [self.view endEditing:YES]; }
- (BOOL)readOptions {
    NSUInteger count = 0, interval = 0;
    if (!numericValue(self.countField.text, &count) || !numericValue(self.intervalField.text, &interval) ||
        !NWBTPingMillisecondsValid(count, interval)) return NO;
    self.pingCount = count; self.intervalMS = interval; return YES;
}
- (void)saveOptions {
    [NSUserDefaults.standardUserDefaults setInteger:self.pingCount forKey:countKey];
    [NSUserDefaults.standardUserDefaults setInteger:self.intervalMS forKey:intervalKey];
}
- (void)textFieldDidEndEditing:(UITextField *)field {
    if (field == self.address || busy) return;
    if ([self readOptions]) [self saveOptions];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone];
}
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (field == self.address) return YES;
    NSString *value = [field.text stringByReplacingCharactersInRange:range withString:string];
    if (value.length > (field == self.countField ? 2 : 4)) return NO;
    for (NSUInteger i = 0; i < value.length; ++i)
        if ([value characterAtIndex:i] < '0' || [value characterAtIndex:i] > '9') return NO;
    return YES;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 5; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; if (section == 2) return 2;
    if (section == 3) return busy ? 2 : 1;
    if (section == 4) return lastReport ? MAX(1, [lastReport[@"samples"] count] + 1) : 1;
    return 1;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    (void)table; return section == 1 ? NWText(@"bt.address") : section == 2 ? NWText(@"bt.options") : section == 4 ? NWText(@"bt.results") : nil;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; return section == 1 ? NWText(@"bt.prepare") : section == 2 ? NWText(@"bt.options_limits") : section == 3 ? NWText(@"bt.limits") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table; UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (index.section == 0) {
        content.text = NWText(@"bt.intro"); content.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
        if (!self.capabilities) content.secondaryText = NWText(@"bt.checking");
        else if (self.capabilities[@"error_code"]) content.secondaryText = NWText([@"bt.error." stringByAppendingString:self.capabilities[@"error_code"]]);
        else content.secondaryText = NWText([self.capabilities[@"supported"] boolValue] ? @"bt.ready" : @"bt.error.unsupported");
        if (lastReport && !busy) content.secondaryText = reportText(lastReport);
    } else if (index.section == 1) {
        self.address.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:self.address];
        UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[self.address.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [self.address.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor], [self.address.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [self.address.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor], [self.address.heightAnchor constraintGreaterThanOrEqualToConstant:30]]]; return cell;
    } else if (index.section == 2) {
        BOOL interval = index.row == 1;
        content.text = NWText(interval ? @"bt.interval_ms" : @"bt.count");
        cell.accessoryView = interval ? self.intervalField : self.countField;
    } else if (index.section == 3) {
        content.text = index.row || busy ? NWText(index.row ? @"bt.cancel" : @"bt.running") :
            NWText(@"bt.start");
        content.image = [UIImage systemImageNamed:index.row ? @"stop.circle" : @"waveform.path"];
        cell.selectionStyle = index.row || (!busy && [self.capabilities[@"supported"] boolValue]) ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        content.textProperties.color = index.row ? UIColor.systemRedColor : NWAccentColor();
    } else if (!lastReport) content.text = NWText(@"bt.empty");
    else if (index.row == 0) {
        NSString *code = lastReport[@"error_code"];
        content.text = reportText(lastReport);
        NSMutableArray<NSString *> *details = [NSMutableArray new];
        NSNumber *interval = lastReport[@"interval_ms"];
        if (!interval && lastReport[@"interval_seconds"]) interval = @([lastReport[@"interval_seconds"] doubleValue] * 1000);
        if (lastReport[@"requested_count"] && interval)
            [details addObject:[NSString stringWithFormat:NWText(@"bt.result_options"),
                [lastReport[@"requested_count"] unsignedIntegerValue], interval.unsignedIntegerValue]];
        if ([lastReport[@"service_restored"] boolValue]) [details addObject:NWText(@"bt.restored")];
        content.secondaryText = [details componentsJoinedByString:@"\n"];
        content.image = [UIImage systemImageNamed:code ? @"exclamationmark.circle" : @"checkmark.circle"];
    } else {
        NSDictionary *sample = lastReport[@"samples"][index.row - 1];
        content.text = [NSString stringWithFormat:NWText(@"bt.sequence"), [sample[@"sequence"] unsignedIntegerValue]];
        content.secondaryText = [sample[@"reply"] boolValue] ? [NSString stringWithFormat:NWText(@"bt.rtt"), [sample[@"rtt_ms"] doubleValue]] :
            NWText([sample[@"rejected"] boolValue] ? @"bt.rejected" : @"bt.timeout");
        content.image = [UIImage systemImageNamed:[sample[@"reply"] boolValue] ? @"checkmark.circle" : @"clock"];
    }
    content.imageProperties.tintColor = NWAccentColor(); cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; if (index.section != 3) return;
    if (index.row && busy) { cancelWorker(); return; }
    if (busy || ![self.capabilities[@"supported"] boolValue]) return;
    [self.view endEditing:YES];
    if (![self readOptions]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bt.error.values")
            message:NWText(@"bt.options_limits") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    [self saveOptions];
    BOOL milliseconds = [self.capabilities[@"supports_ping_milliseconds"] boolValue];
    BOOL seconds = [self.capabilities[@"supports_ping_options"] boolValue] && self.intervalMS % 1000 == 0;
    BOOL defaults = self.pingCount == NWBT_DEFAULT_COUNT && self.intervalMS == NWBT_DEFAULT_INTERVAL_MS;
    if (!milliseconds && !seconds && !defaults) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bt.error.options") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    NSString *address = [[self.address.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\\z" options:0 error:NULL];
    BOOL valid = [pattern firstMatchInString:address ?: @"" options:0 range:NSMakeRange(0, address.length)] != nil &&
        ![address isEqual:@"00:00:00:00:00:00"] && ![address isEqual:@"FF:FF:FF:FF:FF:FF"];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:NWText(valid ? @"bt.start" : @"bt.error.address")
        message:valid ? [NSString stringWithFormat:NWText(@"bt.confirm_options"), self.pingCount, self.intervalMS] : nil preferredStyle:UIAlertControllerStyleAlert];
    if (valid) {
        [confirm addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:NWText(@"bt.start") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action; [self begin:address];
        }]];
    } else [confirm addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (void)begin:(NSString *)address {
    if (busy || NWScanBusy() || NWBulkBusy()) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"bt.error.busy") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (!workerLock) workerLock = [NSObject new];
    if (!NWBTPingMillisecondsValid(self.pingCount, self.intervalMS)) return;
    // Snapshot the selected options before dispatch; controls are locked while busy.
    NSArray<NSString *> *arguments;
    if ([self.capabilities[@"supports_ping_milliseconds"] boolValue])
        arguments = @[@"--ping-ms", address, [NSString stringWithFormat:@"%lu", self.pingCount],
            [NSString stringWithFormat:@"%lu", self.intervalMS]];
    else if ([self.capabilities[@"supports_ping_options"] boolValue] && self.intervalMS % 1000 == 0)
        arguments =
        @[@"--ping", address, [NSString stringWithFormat:@"%lu", self.pingCount],
            [NSString stringWithFormat:@"%lu", self.intervalMS / 1000]];
    else if (self.pingCount == NWBT_DEFAULT_COUNT && self.intervalMS == NWBT_DEFAULT_INTERVAL_MS)
        arguments = @[@"--ping", address];
    else return;
    @synchronized (workerLock) { cancelling = NO; worker = 0; }
    busy = YES; lastReport = nil; [self.address resignFirstResponder];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:reportKey];
    [NSUserDefaults.standardUserDefaults setObject:address forKey:@"NukeWirelessBluetoothTarget"];
    background = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"NukeWirelessBluetoothCleanup" expirationHandler:^{ cancelWorker(); }];
    [NSNotificationCenter.defaultCenter postNotificationName:changed object:nil];
    [self refresh:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *report = invoke(arguments, YES);
        NSData *saved = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
        if (saved) {
            [NSUserDefaults.standardUserDefaults setObject:saved forKey:reportKey];
            [NSUserDefaults.standardUserDefaults synchronize];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            lastReport = report; busy = NO;
            if (background != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:background]; background = UIBackgroundTaskInvalid; }
            [NSNotificationCenter.defaultCenter postNotificationName:changed object:nil];
            [self refresh:nil];
            if (self.view.window && self.navigationController.topViewController == self) {
                [self.tableView layoutIfNeeded];
                [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]
                    atScrollPosition:UITableViewScrollPositionTop animated:YES];
            }
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, NWText(@"bt.finished"));
        });
    });
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated]; self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}
@end

UIViewController *NWBluetoothController(void) { return [NWBluetoothViewController new]; }
