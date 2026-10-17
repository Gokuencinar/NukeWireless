#import "NWBLEHistory.h"
#import "NWBLEAdvertisement.h"
#import "NWBuild.h"
#import <TargetConditionals.h>

NSNotificationName const NWBLEHistoryChanged = @"NukeWirelessBLEHistoryChanged";
@interface NWBLEHistory ()
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSDictionary *> *items;
@property(nonatomic,strong) NSURL *url;
@property(nonatomic,strong) dispatch_queue_t writer;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSInteger storageError;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) double lastFlush;
@end
@implementation NWBLEHistory
+ (instancetype)shared {
    static NWBLEHistory *store; static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        store = [[self alloc] initWithURL:[[documents URLByAppendingPathComponent:@"NukeWireless-BLE" isDirectory:YES] URLByAppendingPathComponent:@"history.json"]];
    }); return store;
}
- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url; _items = [NSMutableDictionary new]; _writer = dispatch_queue_create("app.nukewireless.ble-history",DISPATCH_QUEUE_SERIAL); _loading = YES;
        __weak NWBLEHistory *weak = self;
        dispatch_async(_writer,^{
            NSError *error; NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&error];
            NSArray *records = @[]; NSInteger invalid = 0;
            if (attributes && [attributes fileSize] <= 1024*1024) {
                NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
                NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
                if ([root isKindOfClass:NSDictionary.class] && [root[@"schema_version"] isEqual:@1] &&
                    [root[@"devices"] isKindOfClass:NSArray.class] && [root[@"devices"] count] <= 200) records = NWBLEValidateHistory(root[@"devices"]);
                else invalid = -1;
            } else if (attributes) invalid = -2;
            NSInteger code = error && error.code != NSFileReadNoSuchFileError && error.code != NSFileNoSuchFileError ? error.code : invalid;
            dispatch_async(dispatch_get_main_queue(),^{
                NWBLEHistory *owner = weak; if (!owner) return;
                // A clear while loading invalidates the old on-disk snapshot.
                if (!owner.generation) for (NSDictionary *saved in records) {
                    NSString *identifier = saved[@"identifier"]; NSDictionary *recent = owner.items[identifier];
                    if (!recent) owner.items[identifier] = saved;
                    else {
                        NSMutableDictionary *merged = [recent mutableCopy];
                        for (NSString *key in @[@"name",@"company",@"connectable"]) if (!merged[key] && saved[key]) merged[key] = saved[key];
                        merged[@"seen"] = @(MAX([saved[@"seen"] doubleValue],[recent[@"seen"] doubleValue]));
                        merged[@"firstSeen"] = @([saved[@"firstSeen"] doubleValue] < [recent[@"firstSeen"] doubleValue] ? [saved[@"firstSeen"] doubleValue] : [recent[@"firstSeen"] doubleValue]);
                        merged[@"advertisements"] = @(MIN((NSUInteger)1000000000,[saved[@"advertisements"] unsignedIntegerValue]+[recent[@"advertisements"] unsignedIntegerValue]));
                        owner.items[identifier] = merged;
                    }
                }
                owner.loading = NO; owner.storageError = code; [owner trim]; [owner changed]; [owner flush];
            });
        });
    } return self;
}
- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:NWBLEHistoryChanged object:self]; }
- (NSArray<NSDictionary *> *)records {
    return [self.items.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSComparisonResult result = [b[@"seen"] compare:a[@"seen"]];
        return result == NSOrderedSame ? [a[@"identifier"] compare:b[@"identifier"]] : result;
    }];
}
- (void)trim {
    NSArray *ordered = self.records;
    for (NSUInteger i=200;i<ordered.count;i++) [self.items removeObjectForKey:ordered[i][@"identifier"]];
}
- (void)observe:(NSDictionary *)record atTime:(double)time {
    if (![record[@"identifier"] isKindOfClass:NSString.class]) return;
    NSDictionary *updated = NWBLEHistoryRecord(self.items[record[@"identifier"]],record,time);
    if (!updated) return;
    self.items[updated[@"identifier"]] = updated;
    if (self.items.count > 200) [self trim];
    double now = NSProcessInfo.processInfo.systemUptime;
    if (now - self.lastFlush >= 3) { self.lastFlush = now; [self flush]; }
}
- (NSDictionary *)snapshot {
    return @{@"schema_version":@1,@"build":NW_BUILD_VERSION,@"devices":self.records};
}
- (void)flush {
    if (self.loading || self.storageError) return;
    NSDictionary *snapshot = self.snapshot; NSURL *url = self.url; __weak NWBLEHistory *weak = self;
    dispatch_async(self.writer,^{
        NSError *error; NSFileManager *files = NSFileManager.defaultManager;
        [files createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
        if (data) [data writeToURL:url options:NSDataWritingAtomic error:&error];
        if (!error) {
            NSMutableDictionary *attributes = [@{NSFilePosixPermissions:@0600} mutableCopy];
#if TARGET_OS_IPHONE
            attributes[NSFileProtectionKey] = NSFileProtectionCompleteUntilFirstUserAuthentication;
#endif
            [files setAttributes:attributes ofItemAtPath:url.path error:&error];
        }
        NSInteger code = error.code;
        dispatch_async(dispatch_get_main_queue(),^{ NWBLEHistory *owner = weak; if (owner.storageError != code) { owner.storageError = code; [owner changed]; } });
    });
}
- (void)clear { self.generation++; self.storageError = 0; [self.items removeAllObjects]; [self flush]; [self changed]; }
- (void)exportWithCompletion:(void (^)(NSURL *,NSError *))completion {
    NSDictionary *snapshot = self.snapshot;
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"NukeWireless-BLE-History.json"]];
    dispatch_async(self.writer,^{
        NSError *error; NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:&error];
        BOOL ok = data && [data writeToURL:url options:NSDataWritingAtomic error:&error];
        if (ok) [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ completion(ok && !error ? url : nil,error); });
    });
}
@end
