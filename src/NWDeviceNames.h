#import <Foundation/Foundation.h>

// Session-only, best-effort identity evidence. All methods/callbacks run on main.
NSArray<NSString *> *NWNameServiceTypes(void);
NSString *NWCleanDeviceName(NSString *value);
BOOL NWDeviceNameIsPlaceholder(NSString *value);
#ifdef NW_NAME_TESTING
NSString *NWTestPTRName(NSData *data);
#endif
@interface NWDeviceNames : NSObject
- (instancetype)initWithUpdate:(void (^)(NSString *ip, NSString *mac, NSString *name))update;
- (void)start;
- (void)trackIP:(NSString *)ip mac:(NSString *)mac;
- (void)stop;
- (NSDictionary *)diagnostics;
#ifdef NW_NAME_TESTING
// Inject evidence without accessing the network.
- (void)testBegin;
- (void)testName:(NSString *)name ip:(NSString *)ip mac:(NSString *)mac rank:(NSUInteger)rank;
#endif
@end
