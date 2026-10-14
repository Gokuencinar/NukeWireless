#import <Foundation/Foundation.h>

// Read-only name queries to already discovered peers; callbacks on main.
@interface NWLANNames : NSObject
- (instancetype)initWithUpdate:(void (^)(NSString *, NSString *, NSString *, NSUInteger))update;
- (void)start;
- (void)trackIP:(NSString *)ip mac:(NSString *)mac;
- (void)stop;
- (NSDictionary *)diagnostics;
@end
#ifdef NW_NAME_TESTING
NSURL *NWTestSSDPURL(NSData *data, NSString *ip);
NSString *NWTestUPnPName(NSData *data);
#endif
