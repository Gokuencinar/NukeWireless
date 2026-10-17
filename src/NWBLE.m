#import "NWBLE.h"
#import "NWDiagnosticReport.h"
#import "NWBLEAdvertisement.h"
#import "NWBLEHistory.h"
#import "NWBLEDetail.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import "NWLanguage.h"
#import "NWBluetooth.h"
#import "NWScanBridge.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface NWBLEViewController : UITableViewController <CBCentralManagerDelegate, UISearchResultsUpdating>
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic) BOOL historyMode;
@property(nonatomic) BOOL exporting;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UISegmentedControl *filter;
@property(nonatomic, weak) UIViewController *signalController;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *records;
@property(nonatomic, copy) NSArray<NSDictionary *> *rows;
@property(nonatomic, strong) NSTimer *deadline;
@property(nonatomic, strong) NSTimer *redraw;
@property(nonatomic) BOOL requested;
@property(nonatomic) BOOL scanning;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) NSUInteger discoveries;
@property(nonatomic) BOOL submitted, observedScanning;
- (void)saveDiagnostics:(NSString *)event;
@end

@implementation NWBLEViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"ble.title");
    self.records = [NSMutableDictionary new]; self.rows = @[];
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self; self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = NWText(@"ble.search"); self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO; self.definesPresentationContext = YES;
    self.filter = [[UISegmentedControl alloc] initWithItems:@[NWText(@"ble.filter_all"),NWText(@"ble.filter_named"),NWText(@"ble.filter_connectable")]];
    self.filter.selectedSegmentIndex = 0; [self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,54)];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:self.filter];
    [NSLayoutConstraint activateConstraints:@[[self.filter.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.filter.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.filter.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]]];
    self.tableView.tableHeaderView = header;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(historyChanged:) name:NWBLEHistoryChanged object:NWBLEHistory.shared];
    if (self.historyMode) {
        self.title = NWText(@"ble.history");
        self.navigationItem.rightBarButtonItems = @[
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)],
            [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(exportHistory)]];
        self.navigationItem.rightBarButtonItems.firstObject.accessibilityLabel = NWText(@"ble.history_clear");
        self.navigationItem.rightBarButtonItems.lastObject.accessibilityLabel = NWText(@"ble.history_export");
    }
    self.status = NWText(@"ble.idle");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
    self.tableView.backgroundColor = NWCanvasColor();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    // Creating the manager is deferred until an explicit scan action (TCC prompt).
    [self refreshRows];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar); [self refreshRows];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.central stopScan]; self.central.delegate = nil;
    [self.deadline invalidate]; [self.redraw invalidate];
}
- (void)stop {
    self.requested = NO; self.scanning = NO;
    [self.central stopScan];
    [self.deadline invalidate]; self.deadline = nil;
    [self.redraw invalidate]; self.redraw = nil;
    self.status = NWText(@"ble.stopped"); [NWBLEHistory.shared flush]; [self refreshRows];
    [self saveDiagnostics:@"stopped"];
}
- (void)backgrounded:(NSNotification *)notification { (void)notification; [self stop]; }
- (void)becameActive:(NSNotification *)notification {
    (void)notification;
    // The initial powered-on callback can arrive while the permission alert
    // makes UIApplication inactive. Resume the pending request once active.
    if (self.requested && self.central.state == CBManagerStatePoweredOn) [self startPoweredScan];
}
- (void)saveDiagnostics:(NSString *)event {
    if (self.historyMode) return;
    if (self.central.isScanning) self.observedScanning = YES;
    NSDictionary *diagnostics = @{@"event": event, @"time": @(NSDate.date.timeIntervalSince1970),
        @"manager_created": @(self.central != nil), @"state": @(self.central ? self.central.state : CBManagerStateUnknown),
        @"authorization": @(CBManager.authorization), @"application_state": @(UIApplication.sharedApplication.applicationState),
        @"requested": @(self.requested), @"scan_submitted": @(self.submitted),
        @"observed_corebluetooth_scanning": @(self.observedScanning),
        @"corebluetooth_scanning": @(self.central.isScanning),
        @"discovery_callbacks": @(self.discoveries), @"device_count": @(self.records.count),
        @"history_storage_error": @(NWBLEHistory.shared.storageError), @"history_count": @(NWBLEHistory.shared.records.count)};
    NSString *status = self.requested || self.scanning ? @"running" : self.observedScanning ? (self.records.count ? @"passed" : @"empty") : @"not_run";
    if (CBManager.authorization == CBManagerAuthorizationDenied || CBManager.authorization == CBManagerAuthorizationRestricted ||
        (self.central && (self.central.state == CBManagerStatePoweredOff || self.central.state == CBManagerStateUnsupported))) status = @"blocked";
    NWDiagnosticRecord(@"ble_scan", status, diagnostics);
    [NSUserDefaults.standardUserDefaults setObject:diagnostics forKey:@"NukeWirelessBLELastScan"];
    [NSUserDefaults.standardUserDefaults synchronize];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!self.signalController || self.navigationController.topViewController != self.signalController) [self stop];
}
- (void)refreshRows {
    NSArray *source = self.historyMode ? NWBLEHistory.shared.records : self.records.allValues;
    NSMutableArray *filtered = [NSMutableArray new];
    for (NSDictionary *record in source) if (NWBLEMatchesFilter(record,self.search.searchBar.text,self.filter.selectedSegmentIndex)) [filtered addObject:record];
    self.rows = [filtered sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (self.historyMode) {
            NSComparisonResult order = [b[@"seen"] compare:a[@"seen"]];
            if (order != NSOrderedSame) return order;
        }
        NSInteger ar = a[@"rssi"] ? [a[@"rssi"] integerValue] : -1000;
        NSInteger br = b[@"rssi"] ? [b[@"rssi"] integerValue] : -1000;
        if (ar != br) return ar > br ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"identifier"] compare:b[@"identifier"]];
    }];
    if (self.historyMode) {
        self.navigationItem.rightBarButtonItems.firstObject.enabled = !NWBLEHistory.shared.loading && (NWBLEHistory.shared.records.count > 0 || NWBLEHistory.shared.storageError);
        self.navigationItem.rightBarButtonItems.lastObject.enabled = !self.exporting && !NWBLEHistory.shared.loading && NWBLEHistory.shared.records.count > 0;
    }
    [self.tableView reloadData];
}
- (void)filterChanged { [self refreshRows]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)search { (void)search; [self refreshRows]; }
- (void)historyChanged:(NSNotification *)notification { (void)notification; if (self.historyMode) [self refreshRows]; }
- (void)clearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"ble.history_clear") message:NWText(@"ble.history_clear_hint") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ble.history_clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [NWBLEHistory.shared clear]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)exportHistory {
    if (self.exporting || self.presentedViewController) return;
    self.exporting = YES; [self refreshRows];
    __weak NWBLEViewController *weak = self;
    [NWBLEHistory.shared exportWithCompletion:^(NSURL *url,NSError *error) {
        NWBLEViewController *owner = weak; owner.exporting = NO; [owner refreshRows];
        if (!owner || !owner.view.window || owner.presentedViewController) return;
        if (!url || error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"ble.history_export") message:NWText(@"ble.history_error") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
            [owner presentViewController:alert animated:YES completion:nil]; return;
        }
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        share.popoverPresentationController.barButtonItem = owner.navigationItem.rightBarButtonItems.lastObject;
        [owner presentViewController:share animated:YES completion:nil];
    }];
}
- (void)startPoweredScan {
    if (!self.requested || self.scanning || !self.view.window ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [self saveDiagnostics:@"waiting_for_active_view"]; return;
    }
    if (self.historyMode || NWBluetoothBusy() || NWBulkBusy()) {
        self.requested = NO; self.status = NWText(@"bt.error.busy"); [self refreshRows]; return;
    }
    self.scanning = YES; self.status = NWText(@"ble.scanning");
    [self.central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
    self.submitted = YES;
    [self saveDiagnostics:@"scan_submitted"];
    __weak NWBLEViewController *weakSelf = self;
    self.deadline = [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer) {
        (void)timer; [weakSelf stop];
    }];
    self.redraw = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        if (!weakSelf.observedScanning && weakSelf.central.isScanning) [weakSelf saveDiagnostics:@"scan_confirmed"];
        [weakSelf refreshRows];
    }];
    [self refreshRows];
}
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central != self.central) return;
    [self saveDiagnostics:@"state_changed"];
    if (central.state == CBManagerStatePoweredOn) {
        [self startPoweredScan]; return;
    }
    BOOL pending = self.requested && (central.state == CBManagerStateUnknown || central.state == CBManagerStateResetting);
    [self stop]; self.requested = pending;
    switch (central.state) {
        case CBManagerStateUnauthorized: self.status = NWText(@"ble.denied"); break;
        case CBManagerStatePoweredOff: self.status = NWText(@"ble.off"); break;
        case CBManagerStateUnsupported: self.status = NWText(@"ble.unsupported"); break;
        default: self.status = NWText(@"ble.waiting"); break;
    }
    [self refreshRows];
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
    advertisementData:(NSDictionary<NSString *, id> *)advertisement RSSI:(NSNumber *)RSSI {
    if (central != self.central || !self.scanning) return;
    self.discoveries++;
    NSString *identifier = peripheral.identifier.UUIDString;
    NSDictionary *previous = self.records[identifier];
    if (!previous && self.records.count >= 30) return;
    NSMutableArray<NSString *> *services = [NSMutableArray new];
    for (NSString *key in @[CBAdvertisementDataServiceUUIDsKey, CBAdvertisementDataOverflowServiceUUIDsKey])
        for (CBUUID *uuid in advertisement[key]) [services addObject:uuid.UUIDString];
    NSDictionary *serviceData = advertisement[CBAdvertisementDataServiceDataKey];
    for (CBUUID *uuid in serviceData) [services addObject:uuid.UUIDString];
    self.records[identifier] = NWBLEUpdateRecord(previous, identifier,
        advertisement[CBAdvertisementDataLocalNameKey] ?: peripheral.name, RSSI.integerValue,
        advertisement[CBAdvertisementDataManufacturerDataKey], services,
        advertisement[CBAdvertisementDataIsConnectable], NSProcessInfo.processInfo.systemUptime);
    [NWBLEHistory.shared observe:self.records[identifier] atTime:NSDate.date.timeIntervalSince1970];
    if (self.discoveries == 1 || self.discoveries % 10 == 0) [self saveDiagnostics:@"discovered"];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return self.historyMode ? 1 : 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return !self.historyMode && section == 0 ? 3 : MAX((NSUInteger)1, self.rows.count);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; if (self.historyMode) return NWText(NWBLEHistory.shared.storageError ? @"ble.history_error" : @"ble.history_hint");
    return section == 0 ? NWText(@"ble.limits") : NWText(@"ble.identity");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    if (!self.historyMode && index.section == 0 && index.row == 1) {
        content.text = NWText(@"ble.diagnostics");
        content.secondaryText = [NSString stringWithFormat:NWText(@"ble.scan_counts"), self.discoveries, self.records.count];
        content.image = [UIImage systemImageNamed:@"info.circle"];
    } else if (!self.historyMode && index.section == 0 && index.row == 2) {
        content.text = NWText(@"ble.history"); content.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (!self.historyMode && index.section == 0) {
        content.text = NWText(self.requested || self.scanning ? @"ble.stop" : @"ble.start");
        content.secondaryText = self.status; content.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
    } else if (!self.rows.count) {
        content.text = NWText(self.historyMode ? @"ble.history_empty" : @"ble.empty"); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *record = self.rows[index.row];
        content.text = record[@"name"] ?: NWText(@"ble.unnamed");
        NSString *signal = record[@"rssi"] ? [NSString stringWithFormat:@"%@ dBm", record[@"rssi"]] : NWText(@"ble.unavailable");
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@\n%@", signal, record[@"company"] ?: NWText(@"ble.unknown_company"), record[@"identifier"]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    content.imageProperties.tintColor = NWAccentColor(); cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if (!self.historyMode && index.section == 0 && index.row == 1) {
        [self saveDiagnostics:@"diagnostics_viewed"];
        NSString *message = [NSString stringWithFormat:NWText(@"ble.diagnostic_details"),
            (long)(self.central ? self.central.state : CBManagerStateUnknown), (long)CBManager.authorization,
            NWText(self.central.isScanning ? @"ble.yes" : @"ble.no"), self.discoveries, self.records.count];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"ble.diagnostics")
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (!self.historyMode && index.section == 0 && index.row == 2) {
        NWBLEViewController *history = [NWBLEViewController new]; history.historyMode = YES;
        [self.navigationController pushViewController:history animated:YES]; return;
    }
    if (!self.historyMode && index.section == 0) {
        if (self.requested || self.scanning) { [self stop]; return; }
        if (self.historyMode || NWBluetoothBusy() || NWBulkBusy()) {
            self.status = NWText(@"bt.error.busy"); [self refreshRows]; return;
        }
        [self.records removeAllObjects]; self.discoveries = 0; self.submitted = NO;
        self.observedScanning = NO; self.requested = YES;
        self.status = NWText(@"ble.waiting"); [self refreshRows];
        if (!self.central) self.central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()
            options:@{CBCentralManagerOptionShowPowerAlertKey: @NO}];
        else [self centralManagerDidUpdateState:self.central];
        return;
    }
    if (!self.rows.count) return;
    NSDictionary *record = self.rows[index.row];
    NSString *identifier = record[@"identifier"]; __weak NWBLEViewController *weak = self;
    BOOL historical = self.historyMode;
    UIViewController *detail = NWBLEDetailController(^NSDictionary *{
        NWBLEViewController *owner = weak;
        return historical ? record : owner.records[identifier];
    }, historical, ^BOOL { return weak.scanning; }, ^{ [weak stop]; });
    self.signalController = historical ? nil : detail;
    BOOL animate = YES;
#ifdef NW_UI_TESTING
    animate = NO;
#endif
    [self.navigationController pushViewController:detail animated:animate];
}
@end

UIViewController *NWBLEController(void) { return [NWBLEViewController new]; }

#ifdef NW_UI_TESTING
// State-flow fixture only: no CoreBluetooth manager or radio is instantiated.
@interface NWBLETestCentral : NSObject
@property(nonatomic, weak) id delegate;
@property(nonatomic, getter=isScanning) BOOL scanning;
@property(nonatomic) NSUInteger starts;
@end
@implementation NWBLETestCentral
- (CBManagerState)state { return CBManagerStatePoweredOn; }
- (void)stopScan { self.scanning = NO; }
- (void)scanForPeripheralsWithServices:(NSArray *)services options:(NSDictionary *)options {
    (void)services; (void)options; self.starts++; self.scanning = YES;
}
@end
static int NWBLEWhileWiFiScanUIRegressionCheck(void) {
    if (!NWScanBusy()) return 9;
    NWBLEViewController *controller = [NWBLEViewController new];
    [controller loadViewIfNeeded];
    if (controller.central || controller.scanning || controller.rows.count) return 1;
    controller.records[@"fixture"] = NWBLEUpdateRecord(nil, @"fixture", @"BLE fixture", -65,
        nil, @[@"180F"], @YES, NSProcessInfo.processInfo.systemUptime);
    [controller refreshRows];
    UITableViewCell *cell = [controller tableView:controller.tableView
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    if (![content.text isEqual:@"BLE fixture"] || ![content.secondaryText containsString:@"-65 dBm"]) return 2;
    controller.requested = YES; controller.scanning = YES;
    [controller backgrounded:nil];
    if (controller.requested || controller.scanning || controller.rows.count != 1) return 3;
    controller.requested = YES; [controller viewWillDisappear:NO];
    if (controller.requested || controller.central) return 4;
    NWBLETestCentral *fixture = [NWBLETestCentral new];
    controller.central = (CBCentralManager *)(id)fixture;
    controller.requested = YES;
    [controller startPoweredScan];
    if (!controller.requested || fixture.starts || controller.scanning) return 5;
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 640)];
    [window addSubview:controller.view];
    [controller becameActive:nil];
    if (fixture.starts != 1 || !controller.scanning || !controller.submitted) return 6;
    [controller becameActive:nil];
    if (fixture.starts != 1) return 7;
    controller.search.searchBar.text = @"180f"; [controller refreshRows];
    if (controller.rows.count != 1) return 10;
    controller.search.searchBar.text = @"absent"; [controller refreshRows];
    if (controller.rows.count) return 11;
    controller.search.searchBar.text = nil; controller.filter.selectedSegmentIndex = 2; [controller refreshRows];
    if (controller.rows.count != 1) return 12;
    controller.filter.selectedSegmentIndex = 0;
    [controller stop];
    if (fixture.isScanning || controller.requested || controller.scanning) return 8;
    [controller.view removeFromSuperview];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    [window addSubview:navigation.view]; navigation.view.frame = window.bounds;
    controller.requested = YES; [controller startPoweredScan];
    if (!controller.scanning) return 13;
    [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    UIViewController *detail = navigation.topViewController; [detail loadViewIfNeeded];
    if (detail == controller || !controller.scanning || ![detail.navigationItem.rightBarButtonItem.title isEqual:NWText(@"bt.stop")]) return 14;
    [UIApplication.sharedApplication sendAction:NSSelectorFromString(@"stop") to:detail from:nil forEvent:nil];
    if (controller.scanning || fixture.isScanning) return 15;
    [navigation popViewControllerAnimated:NO]; controller.central = nil;
    [NWBLEHistory.shared clear];
    NSString *uuid = @"A3EF8A7A-69D7-4BB9-BAAC-BE81FE99FE52";
    for (unsigned i=0;i<12;i++) {
        NSDictionary *sample = NWBLEUpdateRecord(nil,uuid,@"BLE fixture TV",-65+(NSInteger)(i%5)*3,nil,@[@"180F"],@YES,i);
        [NWBLEHistory.shared observe:sample atTime:1700000000+i];
    }
    NWBLEViewController *history = [NWBLEViewController new]; history.historyMode = YES;
    [history loadViewIfNeeded];
    if (history.rows.count != 1 || history.central || [history tableView:history.tableView numberOfRowsInSection:0] != 1) return 16;
    NSDictionary *record = history.rows.firstObject;
    UIViewController *graph = NWBLEDetailController(^NSDictionary *{ return record; },YES,nil,nil);
    [graph loadViewIfNeeded]; graph.view.frame = CGRectMake(0,0,390,844); [graph.view layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:graph.view.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context; [graph.view drawViewHierarchyInRect:graph.view.bounds afterScreenUpdates:YES];
    }];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *name = [NSString stringWithFormat:@"%@-ble-signal.png",NWLanguageCode()];
    [UIImagePNGRepresentation(image) writeToURL:[documents URLByAppendingPathComponent:name] atomically:YES];
    [NWBLEHistory.shared clear]; [navigation.view removeFromSuperview];
    return 0;
}
int NWBLEUIRegressionCheck(void) {
    NWBeginWiFiScanUITest();
    @try { return NWBLEWhileWiFiScanUIRegressionCheck(); }
    @finally { NWEndWiFiScanUITest(); }
}
#endif
