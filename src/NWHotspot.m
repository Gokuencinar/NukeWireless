#import "NWHotspot.h"
#import "NWScanBridge.h"
#import "NWPolicy.h"
#import "NWLegacyABI.h"
#import "NWAppearance.h"
#import "NWLanguage.h"
#import "NWResources.h"
#import "NWDiagnosticReport.h"
#import "NWDeviceActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <QuartzCore/QuartzCore.h>
#include <spawn.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
extern char **environ;
extern void NWInvokeRefresh(void *adapter, const void *entry);
static NSMutableDictionary<NSString *, id> *peers;
static NWScanState scan;
static id nativeAdapter;
static __weak id nativeScanner;
static NSString *scanNetwork;
static BOOL returned, changing, checking;
static NSTimer *watchdog;
static NSDictionary *filterStatus;
static NSUInteger filterGeneration;
static dispatch_queue_t filterQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("app.nukewireless.hotspot",DISPATCH_QUEUE_SERIAL); }); return queue;
}
static id object(id value, NSString *key) {
    SEL selector = NSSelectorFromString(key);
    return [value respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(value, selector) : nil;
}
static BOOL localAddress(NSString *address) {
    struct ifaddrs *first = NULL; if (getifaddrs(&first)) return NO;
    BOOL local = NO;
    for (struct ifaddrs *p = first; p; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
        char text[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, text, sizeof(text)) && [address isEqualToString:@(text)]) { local = YES; break; }
    }
    freeifaddrs(first); return local;
}
static NSString *network(void) {
    struct ifaddrs *first = NULL; if (getifaddrs(&first)) return @"";
    NSMutableArray *parts = [NSMutableArray new];
    for (struct ifaddrs *p = first; p; p = p->ifa_next) {
        if (!p->ifa_addr || !p->ifa_netmask || p->ifa_addr->sa_family != AF_INET || strncmp(p->ifa_name, "bridge", 6)) continue;
        [parts addObject:[NSString stringWithFormat:@"%s/%u/%u", p->ifa_name,
            ((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr, ((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr]];
    }
    freeifaddrs(first); [parts sortUsingSelector:@selector(compare:)]; return [parts componentsJoinedByString:@","];
}
static void notify(void) { [NSNotificationCenter.defaultCenter postNotificationName:NWStateChanged object:nil]; }
static void mainBlock(dispatch_block_t block) { if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block); }
static BOOL method(id device, NSString *name, const char *encoding) {
    Method m = class_getInstanceMethod(object_getClass(device), NSSelectorFromString(name));
    return m && !strcmp(method_getTypeEncoding(m), encoding);
}
static NSString *prefix(NSString *mac) { return [@"NukeWirelessHotspot:" stringByAppendingFormat:@"%@:", [[mac stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString]]; }
static BOOL blocked(id device) {
    if (![filterStatus[@"ok"] boolValue] || ![filterStatus[@"enabled"] boolValue]) return NO;
    NSArray *rules = filterStatus[@"rules"]; NSString *key = prefix(object(device, @"macAddress") ?: @"");
    NSDictionary *addresses=filterStatus[@"ipv4"];
    NSString *canonical=[[object(device,@"macAddress") stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
    if (![addresses isKindOfClass:NSDictionary.class] || ![addresses[canonical ?: @""] isEqual:object(device,@"ipAddress")]) return NO;
    return [rules isKindOfClass:NSArray.class] && [rules containsObject:[key stringByAppendingString:@"0:0"]] && [rules containsObject:[key stringByAppendingString:@"0:1"]];
}
static NSArray<NSDictionary *> *snapshot(void) {
    NSMutableArray *rows = [NSMutableArray new];
    for (NSString *ip in peers) {
        id device = peers[ip]; BOOL local = localAddress(ip);
#ifdef NW_UI_TESTING
        if (method(device, @"isLocalDevice", "B16@0:8")) local |= ((BOOL (*)(id,SEL))objc_msgSend)(device, NSSelectorFromString(@"isLocalDevice"));
#endif
        NSString *name = object(device, @"nickName");
        if (!name.length) name = local ? UIDevice.currentDevice.name : object(device, @"hostname");
        [rows addObject:@{@"ip":ip, @"mac":object(device,@"macAddress") ?: @"", @"name":name.length ? name : [NSString stringWithFormat:NWText(@"device.fallback"),ip.pathExtension],
            @"vendor":local ? @"Apple" : object(device,@"brand") ?: @"", @"local":@(local),
            @"nickname":object(device,@"nickName") ?: @"", @"blocked":@(blocked(device)), @"generation":@(scan.generation)}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"local"] boolValue] != [b[@"local"] boolValue]) return [a[@"local"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"ip"] compare:b[@"ip"] options:NSNumericSearch];
    }]; return rows;
}
static id current(NSDictionary *row) {
    if (![row[@"generation"] isKindOfClass:NSNumber.class] || [row[@"generation"] unsignedLongLongValue] != scan.generation || ![scanNetwork isEqual:network()]) return nil;
    id device = peers[row[@"ip"]]; return [(object(device,@"macAddress") ?: @"") isEqual:row[@"mac"]] ? device : nil;
}
static NSDictionary *invoke(NSArray<NSString *> *arguments) {
    NSString *root = [NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent].stringByDeletingLastPathComponent;
    NSString *path = [root stringByAppendingPathComponent:@"usr/libexec/harpy-reloaded/nw-hotspot"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:path]) return @{@"ok":@NO,@"error_code":@"missing"};
    int descriptors[2]; if (pipe(descriptors)) return @{@"ok":@NO,@"error_code":@"transport"};
    char *argv[5] = {(char *)path.UTF8String,NULL,NULL,NULL,NULL};
    if (arguments.count > 3) { close(descriptors[0]); close(descriptors[1]); return @{@"ok":@NO}; }
    for (NSUInteger i=0;i<arguments.count;++i) argv[i+1]=(char *)arguments[i].UTF8String;
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&actions, descriptors[0]); posix_spawn_file_actions_addclose(&actions, descriptors[1]);
    pid_t child=0; int launched=posix_spawn(&child,path.fileSystemRepresentation,&actions,NULL,argv,environ);
    posix_spawn_file_actions_destroy(&actions); close(descriptors[1]);
    if (launched) { close(descriptors[0]); return @{@"ok":@NO,@"error_code":@"permissions"}; }
    fcntl(descriptors[0],F_SETFL,O_NONBLOCK); NSMutableData *data=[NSMutableData new]; BOOL done=NO; int status=0;
    double deadline=CACurrentMediaTime()+4;
    while (CACurrentMediaTime()<deadline && data.length<65536) {
        char buffer[4096]; ssize_t size;
        while ((size=read(descriptors[0],buffer,sizeof(buffer)))>0 && data.length<65536) [data appendBytes:buffer length:size];
        pid_t waited=waitpid(child,&status,WNOHANG);
        if (waited==child || (waited<0 && errno==ECHILD)) { done=YES; break; }
        usleep(10000);
    }
    if (!done) { kill(child,SIGKILL); while (waitpid(child,&status,0)<0 && errno==EINTR) {} }
    else { char buffer[4096]; ssize_t size; while ((size=read(descriptors[0],buffer,sizeof(buffer)))>0 && data.length<65536) [data appendBytes:buffer length:size]; }
    close(descriptors[0]);
    id report=data.length<65536 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (!done || ![report isKindOfClass:NSDictionary.class]) return @{@"ok":@NO,@"error_code":@"transport"};
    if ([report[@"ok"] boolValue] && (!WIFEXITED(status) || WEXITSTATUS(status))) return @{@"ok":@NO,@"error_code":@"transport"};
    return report;
}
static void checkFilter(void) {
    if (checking || changing) return; checking=YES;
    NSUInteger generation=filterGeneration;
    dispatch_async(filterQueue(), ^{
        NSDictionary *report=invoke(@[@"reconcile"]);
        dispatch_async(dispatch_get_main_queue(), ^{ checking=NO; if (generation==filterGeneration && !changing) { filterStatus=report; notify(); } });
    });
}
BOOL NWHotspotBusy(void) { return changing || NWStateBusy(&scan); }
void NWHotspotScannerStarted(id scanner, id adapter) {
    mainBlock(^{
        nativeScanner=scanner; nativeAdapter=adapter; returned=NO;
        if (scan.phase!=NWStarting) NWStateBegin(&scan,CACurrentMediaTime());
        scan.phase=NWScanning; scan.progress=CACurrentMediaTime(); scanNetwork=network(); peers=[NSMutableDictionary new];
        [watchdog invalidate]; uint64_t generation=scan.generation;
        watchdog=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            if (scan.generation!=generation || !NWStateBusy(&scan)) { [timer invalidate]; return; }
            NSOperationQueue *queue=object(nativeScanner,@"queue");
            if (NWStateExpired(&scan,CACurrentMediaTime()) || (returned && !queue.operationCount && CACurrentMediaTime()-scan.progress>2)) NWHotspotFinished(nativeAdapter, peers.count>0);
        }];
        NWDiagnosticRecord(@"hotspot_scan",@"running",@{@"generation":@(scan.generation)}); notify();
    });
}
void NWHotspotStartReturned(id scanner) { mainBlock(^{ if (nativeScanner==scanner) returned=YES; }); }
void NWHotspotFound(id adapter,id device) {
    mainBlock(^{
        if (adapter!=nativeAdapter || !NWStateBusy(&scan)) return;
        NSString *ip=object(device,@"ipAddress"); struct in_addr address;
        if (![ip isKindOfClass:NSString.class] || inet_pton(AF_INET,ip.UTF8String,&address)!=1) return;
        id previous=peers[ip]; BOOL local=localAddress(ip);
#ifdef NW_UI_TESTING
        if (method(device,@"isLocalDevice","B16@0:8")) local |= ((BOOL (*)(id,SEL))objc_msgSend)(device,NSSelectorFromString(@"isLocalDevice"));
#endif
        if (local && method(device,@"setIsLocalDevice:","v20@0:8B16")) ((void (*)(id,SEL,BOOL))objc_msgSend)(device,NSSelectorFromString(@"setIsLocalDevice:"),YES);
        // Keep the richer local record instead of adding an anonymous/private-MAC duplicate.
        if (!previous || !local) peers[ip]=device;
        else if (!object(previous,@"hostname") || [object(previous,@"hostname") hasPrefix:@"Equipo"] || [object(previous,@"hostname") hasPrefix:@"Device"]) {
            NSString *name=object(device,@"hostname"); if (name.length && ![name hasPrefix:@"Equipo"] && ![name hasPrefix:@"Device"]) peers[ip]=device;
        }
        scan.progress=CACurrentMediaTime(); notify();
    });
}
void NWHotspotFinished(id adapter,BOOL success) {
    mainBlock(^{
        if (adapter!=nativeAdapter || !NWStateFinish(&scan,scan.generation,success && [scanNetwork isEqual:network()])) return;
        [watchdog invalidate]; watchdog=nil;
        NWDiagnosticRecord(@"hotspot_scan",scan.phase==NWComplete ? (peers.count ? @"passed":@"empty") : @"failed",@{@"device_count":@(peers.count)});
        notify(); checkFilter();
    });
}
void NWHotspotProgress(id adapter) { mainBlock(^{ if (adapter==nativeAdapter && NWStateBusy(&scan)) scan.progress=CACurrentMediaTime(); }); }
static BOOL refresh(void) {
    NSOperationQueue *queue=object(nativeScanner,@"queue");
    if (!nativeAdapter || NWHotspotBusy() || NWScanBusy() || NWBulkBusy() || queue.operationCount) return NO;
    const uint8_t *base=NULL;
    for (uint32_t i=0;i<_dyld_image_count();++i) {
        const char *name=_dyld_get_image_name(i), *last=name ? strrchr(name,'/') : NULL;
        if (last && !strcmp(last+1,NWLegacyExecutable)) base=(const uint8_t *)_dyld_get_image_header(i);
    }
    static const uint8_t prologue[]={0xff,0xc3,0x01,0xd1,0xfa,0x67,0x02,0xa9,0xf8,0x5f,0x03,0xa9,0xf6,0x57,0x04,0xa9};
    if (!base || memcmp(base+0xc5a8,prologue,sizeof(prologue))) return NO;
    NWStateBegin(&scan,CACurrentMediaTime()); notify(); NWInvokeRefresh((__bridge void *)nativeAdapter,base+0xc5a8); return YES;
}
@interface NWHotspotViewController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary *> *rows;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UIBarButtonItem *reload;
@end
@implementation NWHotspotViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=NWText(@"tabs.hotspot"); self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=100;
    self.reload=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(reloadDevices:)];
    self.reload.accessibilityLabel=NWText(@"refresh"); self.reload.accessibilityIdentifier=@"nw.hotspot.refresh";
    self.navigationItem.rightBarButtonItem=self.reload;
    self.refreshControl=[UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(reloadDevices:) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:NWStateChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update) name:NWAppearanceChanged object:nil]; [self update];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; checkFilter();
    __weak NWHotspotViewController *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer) { (void)timer; if (weakSelf.view.window && UIApplication.sharedApplication.applicationState==UIApplicationStateActive) checkFilter(); }];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self.timer invalidate]; self.timer=nil; }
- (void)dealloc { [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.isViewLoaded) [self update]; }
- (void)update {
    self.rows=snapshot(); self.tableView.backgroundColor=NWCanvasColor(); self.tableView.tintColor=NWAccentColor(); NWStyleNavigationBar(self.navigationController.navigationBar);
    self.reload.enabled=!NWHotspotBusy() && !NWScanBusy() && !NWBulkBusy();
    if (!NWStateBusy(&scan)) [self.refreshControl endRefreshing];
    [self.tableView reloadData];
}
- (void)message:(NSString *)text {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:self.title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ok") style:UIAlertActionStyleDefault handler:nil]];
    if (!self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)reloadDevices:(id)sender { (void)sender; if (!refresh()) { [self.refreshControl endRefreshing]; [self message:NWText(@"hotspot.refreshUnavailable")]; } }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return MAX((NSUInteger)1,self.rows.count); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)table; UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NWStyleCell(cell);
    UIListContentConfiguration *content=cell.defaultContentConfiguration; content.textProperties.numberOfLines=0; content.secondaryTextProperties.numberOfLines=0;
    if (!self.rows.count) {
        content.text=NWText(NWStateBusy(&scan) ? @"scan.scanning" : @"hotspot.empty"); content.secondaryText=NWText(@"hotspot.emptyHint"); content.image=[UIImage systemImageNamed:@"personalhotspot"];
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *row=self.rows[index.row]; content.text=row[@"name"];
        NSString *state=[row[@"local"] boolValue] ? NWText(@"browser.local") : [row[@"blocked"] boolValue] ? NWText(@"browser.blocked") : row[@"vendor"];
        content.secondaryText=[NSString stringWithFormat:@"%@ · %@\n%@",row[@"ip"],state,row[@"mac"]];
        content.image=[UIImage systemImageNamed:[row[@"local"] boolValue] ? @"iphone" : [row[@"blocked"] boolValue] ? @"hand.raised.fill" : @"network"];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.accessibilityHint=NWText(@"browser.actionsHint");
    }
    cell.contentConfiguration=content; return cell;
}
- (void)renameDevice:(NSDictionary *)row {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:NWNativeText(@"Rename Device") message:row[@"ip"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text=[row[@"nickname"] length] ? row[@"nickname"] : row[@"name"]; field.placeholder=NWNativeText(@"Enter new name"); field.clearButtonMode=UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"browser.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; NSString *name=[weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; [self setName:name.length ? name:nil row:row];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)setName:(NSString *)name row:(NSDictionary *)row {
    id device=current(row); if (!device || changing || !method(device,@"setNickName:","v24@0:8@16")) { [self message:NWText(@"browser.actionRetry")]; return; }
    @try { ((void (*)(id,SEL,id))objc_msgSend)(device,NSSelectorFromString(@"setNickName:"),name); }
    @catch (NSException *exception) { (void)exception; [self message:NWText(@"browser.actionRetry")]; return; }
    notify();
}
- (void)setBlocked:(BOOL)value row:(NSDictionary *)row {
    if (!current(row) || [row[@"local"] boolValue] || NWHotspotBusy() || NWScanBusy() || NWBulkBusy()) { [self message:NWText(@"browser.actionRetry")]; return; }
    changing=YES; ++filterGeneration; notify();
    dispatch_async(filterQueue(), ^{
        NSDictionary *report=invoke(@[value ? @"block":@"unblock",row[@"ip"],row[@"mac"]]);
        dispatch_async(dispatch_get_main_queue(), ^{
            changing=NO; filterStatus=report; notify();
            id device=current(row);
            BOOL success=[report[@"ok"] boolValue] && device && blocked(device)==value;
            NWDiagnosticRecord(@"hotspot_block",success ? @"applied":@"failed",@{@"error_code":report[@"error_code"] ?: @"",@"block_requested":@(value)});
            if (!success) [self message:[NSString stringWithFormat:NWText(@"hotspot.blockFailed"),report[@"error_code"] ?: @"verification"]];
        });
    });
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; if (!self.rows.count || self.presentedViewController) return;
    NSDictionary *row=self.rows[index.row]; BOOL value=[row[@"blocked"] boolValue];
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:row[@"name"] message:[NSString stringWithFormat:@"%@\n%@\n%@",row[@"ip"],row[@"mac"],row[@"vendor"]] preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *toggle=[UIAlertAction actionWithTitle:NWNativeText(value ? @"Unblock Device":@"Block Device") style:value ? UIAlertActionStyleDefault:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [self setBlocked:!value row:row]; }];
    toggle.enabled=![row[@"local"] boolValue] && !NWHotspotBusy() && !NWScanBusy() && !NWBulkBusy(); [menu addAction:toggle];
    UIAlertAction *rename=[UIAlertAction actionWithTitle:NWNativeText(@"Rename Device") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; [self renameDevice:row]; }];
    rename.enabled=current(row)!=nil && !changing; [menu addAction:rename];
    UIAlertAction *clear=[UIAlertAction actionWithTitle:NWNativeText(@"Clear Nickname") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; [self setName:nil row:row]; }];
    clear.enabled=rename.enabled && [row[@"nickname"] length]>0; [menu addAction:clear];
    [menu addAction:[UIAlertAction actionWithTitle:NWText(@"browser.copyIP") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; UIPasteboard.generalPasteboard.string=row[@"ip"]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView=table; menu.popoverPresentationController.sourceRect=[table rectForRowAtIndexPath:index];
    [self presentViewController:menu animated:YES completion:nil];
}
@end
UIViewController *NWHotspotController(void) { return [NWHotspotViewController new]; }

#ifdef NW_UI_TESTING
static NWScanState savedHotspotScan;
static NSMutableDictionary *savedHotspotPeers;
static id savedHotspotAdapter;
static NSString *savedHotspotNetwork;
static UINavigationController *testHotspotNavigation;
static void beginHotspotFixture(void) {
    savedHotspotScan=scan; savedHotspotPeers=peers; savedHotspotAdapter=nativeAdapter; savedHotspotNetwork=scanNetwork;
    nativeAdapter=[NSObject new]; peers=[NSMutableDictionary new]; NWStateBegin(&scan,CACurrentMediaTime()); scanNetwork=network();
    for (NSArray *values in @[@[@"iPhone",@"172.20.10.1",@"00:11:22:33:44:66",@YES],
                             @[@"Equipo .1",@"172.20.10.1",@"02:11:22:33:44:77",@YES],
                             @[@"iPhone cliente",@"172.20.10.2",@"02:11:22:33:44:55",@NO]]) {
        id device=[NSClassFromString(@NWLegacyDeviceClass) new];
        for (NSUInteger i=0;i<3;++i) ((void (*)(id,SEL,id))objc_msgSend)(device,NSSelectorFromString(@[@"setHostname:",@"setIpAddress:",@"setMacAddress:"][i]),values[i]);
        ((void (*)(id,SEL,BOOL))objc_msgSend)(device,NSSelectorFromString(@"setIsLocalDevice:"),[values[3] boolValue]);
        NWHotspotFound(nativeAdapter,device);
    }
    NWStateFinish(&scan,scan.generation,YES);
}
static void endHotspotFixture(void) { scan=savedHotspotScan; peers=savedHotspotPeers; nativeAdapter=savedHotspotAdapter; scanNetwork=savedHotspotNetwork; }
int NWHotspotUIRegressionCheck(void) {
    beginHotspotFixture();
    @try {
        NSArray *rows=snapshot(); if (rows.count!=2 || ![rows[0][@"local"] boolValue] || [rows[1][@"local"] boolValue]) return 1;
        if (![object(peers[@"172.20.10.1"],@"hostname") isEqual:@"iPhone"]) return 2;
        NSDictionary *row=rows[1]; if (!current(row)) return 3;
        NSMutableDictionary *stale=[row mutableCopy]; stale[@"generation"]=@(scan.generation+1); if (current(stale)) return 4;
        stale=[row mutableCopy]; stale[@"mac"]=@"02:11:22:33:44:99"; if (current(stale)) return 5;
        scanNetwork=@"changed"; if (current(row)) return 6;
        scanNetwork=network(); scan.phase=NWScanning; if (refresh()) return 7;
        return 0;
    } @finally { endHotspotFixture(); }
}
int NWHotspotUIRegressionPresent(int phase) {
    if (phase==0) {
        beginHotspotFixture(); UIViewController *root=nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) root=window.rootViewController;
        if (!root || root.presentedViewController) { endHotspotFixture(); return 1; }
        testHotspotNavigation=[[UINavigationController alloc] initWithRootViewController:NWHotspotController()];
        testHotspotNavigation.modalPresentationStyle=UIModalPresentationFullScreen;
        [root presentViewController:testHotspotNavigation animated:NO completion:nil]; return 0;
    }
    NWHotspotViewController *controller=(id)testHotspotNavigation.topViewController;
    if (phase==1) {
        if (controller.rows.count!=2 || !controller.reload.enabled) return 2;
        [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UINavigationController *localMenu=(id)controller.presentedViewController;
        UITableViewController *sheet=(id)localMenu.topViewController;
        UITableViewCell *blockCell=[sheet tableView:sheet.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
        if (!(blockCell.accessibilityTraits & UIAccessibilityTraitNotEnabled)) return 3;
        [localMenu dismissViewControllerAnimated:NO completion:^{
            [controller tableView:controller.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        }]; return 0;
    }
    if (phase==2) {
        BOOL visible=controller.presentedViewController.view.window!=nil;
        [testHotspotNavigation dismissViewControllerAnimated:NO completion:nil]; testHotspotNavigation=nil; endHotspotFixture();
        return visible ? 0 : 4;
    }
    return 5;
}
#endif
