#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSNotificationName const NWBLEHistoryChanged;
@interface NWBLEHistory : NSObject
+ (instancetype)shared;
- (instancetype)initWithURL:(NSURL *)url;
- (void)observe:(NSDictionary *)record atTime:(double)time;
- (NSArray<NSDictionary *> *)records;
- (void)flush;
- (void)clear;
- (void)exportWithCompletion:(void (^)(NSURL *, NSError *))completion;
@property(nonatomic,readonly) BOOL loading;
@property(nonatomic,readonly) NSInteger storageError;
@end
