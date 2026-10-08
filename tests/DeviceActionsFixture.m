#import <Foundation/Foundation.h>
#include <unistd.h>

// Simulator-only stand-ins for the verified Objective-C contracts. No network I/O.
@interface _TtC13HarpyReloaded8MMDevice : NSObject
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *ipAddress;
@property(nonatomic, copy) NSString *macAddress;
@property(nonatomic, copy) NSString *brand;
@property(nonatomic, copy) NSString *nickName;
@property(nonatomic) BOOL isLocalDevice;
@property(nonatomic) BOOL isBlocking;
@end
@implementation _TtC13HarpyReloaded8MMDevice
@end
static NSMutableSet *fixtureBlocks;
static NSMutableArray *fixtureCalls;
void NWResetDeviceCommandFixture(void) { fixtureBlocks = [NSMutableSet new]; fixtureCalls = [NSMutableArray new]; }
NSArray *NWDeviceCommandFixtureCalls(void) { return [fixtureCalls copy]; }
@interface _TtC13HarpyReloaded10MCCommands : NSObject
@end
@implementation _TtC13HarpyReloaded10MCCommands
+ (NSArray *)runningBlocksForIpWithIp:(NSString *)ip { return [fixtureBlocks containsObject:ip] ? @[@(getpid())] : @[]; }
+ (NSArray *)runningBlocksForArp { return fixtureBlocks.count ? @[@(getpid())] : @[]; }
+ (void)blockGivenIPWithIp:(NSString *)ip targetMac:(NSString *)mac {
    [fixtureCalls addObject:@[@"block", ip, mac]]; [fixtureBlocks addObject:ip];
}
+ (void)unblockIPWithIp:(NSString *)ip { [fixtureCalls addObject:@[@"unblock", ip]]; [fixtureBlocks removeObject:ip]; }
@end
