#import "NWBLE.h"
#import "NWBLEAdvertisement.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import "NWBluetooth.h"
#import "NWScanBridge.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface NWBLEViewController : UITableViewController <CBCentralManagerDelegate>
@property(nonatomic, strong) CBCentralManager *central;
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
    self.status = NWText(@"ble.idle");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
    self.tableView.backgroundColor = NWCanvasColor();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgrounded:)
        name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    // Creating the manager is deferred until an explicit scan action (TCC prompt).
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar);
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
    self.status = NWText(@"ble.stopped"); [self refreshRows];
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
    if (self.central.isScanning) self.observedScanning = YES;
    NSDictionary *diagnostics = @{@"event": event, @"time": @(NSDate.date.timeIntervalSince1970),
        @"manager_created": @(self.central != nil), @"state": @(self.central ? self.central.state : CBManagerStateUnknown),
        @"authorization": @(CBManager.authorization), @"application_state": @(UIApplication.sharedApplication.applicationState),
        @"requested": @(self.requested), @"scan_submitted": @(self.submitted),
        @"observed_corebluetooth_scanning": @(self.observedScanning),
        @"corebluetooth_scanning": @(self.central.isScanning),
        @"discovery_callbacks": @(self.discoveries), @"device_count": @(self.records.count)};
    [NSUserDefaults.standardUserDefaults setObject:diagnostics forKey:@"NukeWirelessBLELastScan"];
    [NSUserDefaults.standardUserDefaults synchronize];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; [self stop];
}
- (void)refreshRows {
    self.rows = [self.records.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ar = a[@"rssi"] ? [a[@"rssi"] integerValue] : -1000;
        NSInteger br = b[@"rssi"] ? [b[@"rssi"] integerValue] : -1000;
        if (ar != br) return ar > br ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"identifier"] compare:b[@"identifier"]];
    }];
    [self.tableView reloadData];
}
- (void)startPoweredScan {
    if (!self.requested || self.scanning || !self.view.window ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [self saveDiagnostics:@"waiting_for_active_view"]; return;
    }
    if (NWBluetoothBusy() || NWScanBusy() || NWBulkBusy()) {
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
    if (self.discoveries == 1 || self.discoveries % 10 == 0) [self saveDiagnostics:@"discovered"];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? 2 : MAX((NSUInteger)1, self.rows.count);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; return section == 0 ? NWText(@"ble.limits") : NWText(@"ble.identity");
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NWStyleCell(cell); UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    if (index.section == 0 && index.row == 1) {
        content.text = NWText(@"ble.diagnostics");
        content.secondaryText = [NSString stringWithFormat:NWText(@"ble.scan_counts"), self.discoveries, self.records.count];
        content.image = [UIImage systemImageNamed:@"info.circle"];
    } else if (index.section == 0) {
        content.text = NWText(self.requested || self.scanning ? @"ble.stop" : @"ble.start");
        content.secondaryText = self.status; content.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
    } else if (!self.rows.count) {
        content.text = NWText(@"ble.empty"); cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
    if (index.section == 0 && index.row == 1) {
        [self saveDiagnostics:@"diagnostics_viewed"];
        NSString *message = [NSString stringWithFormat:NWText(@"ble.diagnostic_details"),
            (long)(self.central ? self.central.state : CBManagerStateUnknown), (long)CBManager.authorization,
            NWText(self.central.isScanning ? @"ble.yes" : @"ble.no"), self.discoveries, self.records.count];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"ble.diagnostics")
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (index.section == 0) {
        if (self.requested || self.scanning) { [self stop]; return; }
        if (NWBluetoothBusy() || NWScanBusy() || NWBulkBusy()) {
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
    NSData *manufacturer = record[@"manufacturer"];
    NSMutableString *hex = [NSMutableString new];
    const uint8_t *bytes = manufacturer.bytes;
    for (NSUInteger i = 0; i < MIN(manufacturer.length, (NSUInteger)64); ++i)
        [hex appendFormat:@"%02X%@", bytes[i], i + 1 < manufacturer.length ? @" " : @""];
    if (manufacturer.length > 64) [hex appendString:@"…"];
    NSString *services = [record[@"services"] componentsJoinedByString:@", "];
    NSString *connectable = record[@"connectable"] ? NWText([record[@"connectable"] boolValue] ? @"ble.yes" : @"ble.no") : NWText(@"ble.unavailable");
    NSString *message = [NSString stringWithFormat:NWText(@"ble.details"), record[@"identifier"],
        record[@"rssi"] ? [NSString stringWithFormat:@"%@ dBm", record[@"rssi"]] : NWText(@"ble.unavailable"),
        record[@"company"] ?: NWText(@"ble.unknown_company"), services.length ? services : NWText(@"ble.none"),
        connectable, NSProcessInfo.processInfo.systemUptime - [record[@"seen"] doubleValue],
        hex.length ? hex : NWText(@"ble.none")];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:record[@"name"] ?: NWText(@"ble.unnamed")
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
int NWBLEUIRegressionCheck(void) {
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
    [controller stop];
    if (fixture.isScanning || controller.requested || controller.scanning) return 8;
    [controller.view removeFromSuperview]; controller.central = nil;
    return 0;
}
#endif
