#import <Foundation/Foundation.h>
#import "../src/compat/NWWiFiUnblock.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

static NSUInteger originals, preparations, stops;
static BOOL throwNative;
static char stoppedIP[16];
@interface NativeCommands : NSObject
+ (void)unblockIPWithIp:(NSString *)ip;
@end
@implementation NativeCommands
+ (void)unblockIPWithIp:(NSString *)ip {
    (void)ip; ++originals;
    if (throwNative) @throw [NSException exceptionWithName:@"NativeStopFailure" reason:nil userInfo:nil];
}
@end
@interface AppCommands : NativeCommands @end
@implementation AppCommands @end
@interface WrongCommands : NSObject
+ (int)unblockIPWithIp:(NSString *)ip;
@end
@implementation WrongCommands
+ (int)unblockIPWithIp:(NSString *)ip { (void)ip; return 0; }
@end
static void prepare(const char *ip) { assert(!strcmp(ip,"192.168.1.45")); ++preparations; }
static void stop(const char *ip) { strlcpy(stoppedIP,ip,sizeof(stoppedIP)); ++stops; }

int main(void) { @autoreleasepool {
    assert(!NWInstallWiFiUnblock(Nil,prepare,stop));
    assert(!NWInstallWiFiUnblock(WrongCommands.class,prepare,stop));
    assert(!NWInstallWiFiUnblock(AppCommands.class,prepare,NULL));
    assert(NWInstallWiFiUnblock(AppCommands.class,prepare,stop));
    assert(NWInstallWiFiUnblock(AppCommands.class,prepare,stop));
    [AppCommands unblockIPWithIp:@"192.168.1.45"];
    assert(originals==1 && preparations==1 && stops==1 && !strcmp(stoppedIP,"192.168.1.45"));
    // Repetition must call original and matching cleanup exactly once each.
    [AppCommands unblockIPWithIp:@"192.168.1.45"];
    assert(originals==2 && preparations==2 && stops==2);
    [NativeCommands unblockIPWithIp:@"192.168.1.45"];
    assert(originals==3 && preparations==2 && stops==2); // superclass untouched
    [AppCommands unblockIPWithIp:@"not-an-ip"];
    [AppCommands unblockIPWithIp:nil];
    assert(originals==5 && preparations==2 && stops==2);
    throwNative=YES;
    @try { [AppCommands unblockIPWithIp:@"192.168.1.45"]; assert(0); }
    @catch (NSException *exception) { assert([exception.name isEqual:@"NativeStopFailure"]); }
    assert(originals==6 && preparations==3 && stops==3);
    puts("Wi-Fi Objective-C unblock: ABI guard, original, matching cleanup, repetition, superclass and exception cleanup passed");
    return 0;
} }
