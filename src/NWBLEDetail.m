#import "NWBLEDetail.h"
#import "NWAppearance.h"
#import "NWResources.h"

@interface NWBLESignalView : UIView
@property(nonatomic,copy) NSArray<NSDictionary *> *samples;
@end
@implementation NWBLESignalView
- (void)drawRect:(CGRect)rect {
    (void)rect; CGRect plot = CGRectInset(self.bounds,22,30); plot.origin.x += 26; plot.size.width -= 26;
    [NWPanelColor() setFill]; UIRectFill(self.bounds);
    NSDictionary *style = @{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],NSForegroundColorAttributeName:UIColor.secondaryLabelColor};
    for (int signal=-120;signal<=0;signal+=30) {
        CGFloat y = CGRectGetMaxY(plot) - ((signal+127)/147.0)*plot.size.height;
        [UIColor.separatorColor setStroke]; UIBezierPath *line = [UIBezierPath bezierPath];
        [line moveToPoint:CGPointMake(plot.origin.x,y)]; [line addLineToPoint:CGPointMake(CGRectGetMaxX(plot),y)]; [line stroke];
        [[NSString stringWithFormat:@"%d",signal] drawAtPoint:CGPointMake(4,y-7) withAttributes:style];
    }
    [@"dBm" drawAtPoint:CGPointMake(4,6) withAttributes:style];
    [NWText(@"ble.signal_time") drawAtPoint:CGPointMake(plot.origin.x,CGRectGetMaxY(self.bounds)-22) withAttributes:style];
    if (!self.samples.count) {
        [NWText(@"ble.signal_empty") drawInRect:CGRectInset(plot,5,20) withAttributes:style]; return;
    }
    double first = [self.samples.firstObject[@"time"] doubleValue], last = [self.samples.lastObject[@"time"] doubleValue];
    UIBezierPath *line = [UIBezierPath bezierPath]; NSUInteger index = 0;
    for (NSDictionary *sample in self.samples) {
        CGFloat x = plot.origin.x + ([sample[@"time"] doubleValue]-first)/MAX(1,last-first)*plot.size.width;
        CGFloat y = CGRectGetMaxY(plot) - ([sample[@"rssi"] doubleValue]+127)/147.0*plot.size.height;
        CGPoint point = CGPointMake(x,y); if (index++) [line addLineToPoint:point]; else [line moveToPoint:point];
        [NWAccentColor() setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x-2,y-2,4,4)] fill];
    }
    [NWAccentColor() setStroke]; line.lineWidth = 2; [line stroke];
}
@end
@interface NWBLEDetailViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *(^provider)(void);
@property(nonatomic,copy) BOOL (^scanning)(void);
@property(nonatomic,copy) dispatch_block_t stopScan;
@property(nonatomic) BOOL historical;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NWBLESignalView *graph;
@property(nonatomic,copy) NSDictionary *record;
@end
@implementation NWBLEDetailViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.tableView.backgroundColor = NWCanvasColor();
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 65;
    self.graph = [[NWBLESignalView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,215)];
    self.graph.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.graph.isAccessibilityElement = YES; self.graph.accessibilityLabel = NWText(@"ble.signal_graph");
    self.tableView.tableHeaderView = self.graph; [self refresh];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar); [self refresh]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self resume];
}
- (void)suspend { [self.timer invalidate]; self.timer = nil; }
- (void)resume {
    if (!self.view.window) return;
    __weak NWBLEDetailViewController *weak = self;
    [self.timer invalidate]; self.timer = [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer) { (void)timer; [weak refresh]; }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer = nil;
    // Returning to the list keeps the same bounded scan; leaving this area stops it.
    if (!self.isMovingFromParentViewController && self.stopScan) self.stopScan();
}
- (void)dealloc { [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)stop { if (self.stopScan) self.stopScan(); [self refresh]; }
- (void)refresh {
    self.record = self.provider() ?: @{};
    self.title = self.record[@"name"] ?: NWText(@"ble.signal_title");
    self.navigationItem.rightBarButtonItem = self.scanning && self.scanning() ?
        [[UIBarButtonItem alloc] initWithTitle:NWText(@"bt.stop") style:UIBarButtonItemStylePlain target:self action:@selector(stop)] : nil;
    self.graph.samples = self.record[@"samples"] ?: @[]; [self.graph setNeedsDisplay];
    NSArray *samples = self.graph.samples; double sum=0; NSInteger minimum=20,maximum=-127;
    for (NSDictionary *sample in samples) { NSInteger r=[sample[@"rssi"] integerValue]; sum+=r; minimum=MIN(minimum,r); maximum=MAX(maximum,r); }
    self.graph.accessibilityValue = samples.count ? [NSString stringWithFormat:NWText(@"ble.signal_summary"),sum/samples.count,(long)minimum,(long)maximum] : NWText(@"ble.signal_empty");
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return 9; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { (void)table; (void)section; return NWText(@"ble.signal_hint"); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table; UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; NWStyleCell(cell);
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.numberOfLines = content.secondaryTextProperties.numberOfLines = 0;
    content.text = NWText(@[@"ble.signal_current",@"ble.signal_graph",@"ble.history_seen",@"ble.history_count",@"ble.manufacturer",@"ble.services",@"ble.uuid",@"ble.filter_connectable",@"ble.manufacturer_data"][index.row]);
    NSDictionary *r = self.record; NSString *value;
    switch (index.row) {
        case 0: value = r[@"rssi"] ? [NSString stringWithFormat:@"%@ dBm",r[@"rssi"]] : NWText(@"ble.unavailable"); break;
        case 1: value = self.graph.accessibilityValue; break;
        case 2:
            if (self.historical) {
                NSDateFormatter *format = [NSDateFormatter new]; format.dateStyle = NSDateFormatterShortStyle; format.timeStyle = NSDateFormatterMediumStyle;
                value = [NSString stringWithFormat:@"%@ → %@",[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"firstSeen"] doubleValue]]],
                    [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"seen"] doubleValue]]]];
            } else value = [NSString stringWithFormat:NWText(@"ble.session_seen"),
                MAX(0,NSProcessInfo.processInfo.systemUptime-[r[@"firstSeen"] doubleValue]),MAX(0,NSProcessInfo.processInfo.systemUptime-[r[@"seen"] doubleValue])];
            break;
        case 3: value = [r[@"advertisements"] stringValue] ?: @"0"; break;
        case 4: value = r[@"company"] ?: NWText(@"ble.unknown_company"); break;
        case 5: value = [r[@"services"] componentsJoinedByString:@", "]; if (!value.length) value = NWText(@"ble.none"); break;
        case 6: value = r[@"identifier"] ?: NWText(@"ble.unavailable"); break;
        case 7: value = r[@"connectable"] ? NWText([r[@"connectable"] boolValue] ? @"ble.yes" : @"ble.no") : NWText(@"ble.unavailable"); break;
        default: {
            NSData *data = r[@"manufacturer"]; const uint8_t *bytes = data.bytes; NSMutableString *hex = [NSMutableString new];
            for (NSUInteger i=0;i<MIN(data.length,(NSUInteger)64);i++) [hex appendFormat:@"%02X ",bytes[i]];
            if (data.length > 64) [hex appendString:@"…"];
            value = hex.length ? hex : NWText(self.historical ? @"ble.history_payload_omitted" : @"ble.none"); break;
        }
    }
    content.secondaryText = value; cell.contentConfiguration = content; cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
}
@end
UIViewController *NWBLEDetailController(NSDictionary *(^record)(void), BOOL historical, BOOL (^scanning)(void), dispatch_block_t stop) {
    NWBLEDetailViewController *view = [[NWBLEDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    view.provider = record; view.historical = historical; view.scanning = scanning; view.stopScan = stop; return view;
}
