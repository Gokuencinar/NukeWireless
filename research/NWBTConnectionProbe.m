// One normal iOS connection request to the user's already-paired Mi earbuds.
// No raw HCI, discovery, unpairing, firmware changes or repeated requests.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <sys/sysctl.h>
#include <dispatch/dispatch.h>

static BOOL signature(Class cls, SEL selector, BOOL meta, const char *result, const char *argument) {
    Method method = meta ? class_getClassMethod(cls,selector) : class_getInstanceMethod(cls,selector);
    char found[64]={0},parameter[64]={0};
    if (!method || method_getNumberOfArguments(method)!=(argument ? 3u : 2u)) return NO;
    method_getReturnType(method,found,sizeof found);
    if (strcmp(found,result)) return NO;
    if (argument) {
        method_getArgumentType(method,2,parameter,sizeof parameter);
        if (strcmp(parameter,argument)) return NO;
    }
    return YES;
}
static id objectValue(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if (!signature(object_getClass(object),selector,NO,"@",NULL)) return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object,selector);
}
static NSNumber *booleanValue(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if (!signature(object_getClass(object),selector,NO,"B",NULL)) return nil;
    return @(((BOOL (*)(id,SEL))objc_msgSend)(object,selector));
}
static void pump(double seconds) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while (deadline.timeIntervalSinceNow>0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static NSArray *methods(Class cls) {
    NSMutableArray *records=[NSMutableArray new];
    for (NSString *name in @[@"name",@"address",@"paired",@"connected",@"isConnected",@"connecting",@"connect",@"disconnect"]) {
        Method method=class_getInstanceMethod(cls,NSSelectorFromString(name));
        if (method) [records addObject:@{@"selector":name,@"encoding":[NSString stringWithUTF8String:method_getTypeEncoding(method)]}];
    }
    return records;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        BOOL connect=argc==2 && !strcmp(argv[1],"--connect-once");
        if (argc!=1 && !connect) return 2;
        NSMutableDictionary *report=[@{@"tool":@"NWBTConnectionProbe-2",@"request_submitted":@NO,
            @"connection_requests":@0,@"radio_state_modified":@NO,@"raw_hci_commands":@0,
            @"laptop_disconnection_verified":@NO} mutableCopy];
        @try {
            char machine[128]={0};size_t size=sizeof machine;
            sysctlbyname("hw.machine",machine,&size,NULL,0);
            report[@"machine"]=[NSString stringWithUTF8String:machine];
            report[@"ios"]=NSProcessInfo.processInfo.operatingSystemVersionString;
            if (strcmp(machine,"iPhone11,2") || ![report[@"ios"] containsString:@"16.3.1"])
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Unsupported device/build." userInfo:nil];
            if (!dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",RTLD_LAZY|RTLD_LOCAL))
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"BluetoothManager unavailable." userInfo:nil];
            Class cls=NSClassFromString(@"BluetoothManager");
            SEL setQueue=NSSelectorFromString(@"setSharedInstanceQueue:");
            if (!signature(cls,setQueue,YES,"v","@"))
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Manager callback queue ABI mismatch." userInfo:nil];
            // A CLI process has no UIApplication main loop. Service the legacy
            // manager's asynchronous session callbacks on a dedicated queue.
            dispatch_queue_t queue=dispatch_queue_create("me.midnightchips.nw.connection-probe",DISPATCH_QUEUE_SERIAL);
            ((void (*)(id,SEL,id))objc_msgSend)(cls,setQueue,queue);
            SEL shared=NSSelectorFromString(@"sharedInstance");
            if (!signature(cls,shared,YES,"@",NULL))
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Manager factory ABI mismatch." userInfo:nil];
            id manager=((id (*)(id,SEL))objc_msgSend)(cls,shared);
            if (!manager) @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Manager unavailable." userInfo:nil];
            pump(3);
            SEL initError=NSSelectorFromString(@"lastInitError");
            if (signature(cls,initError,YES,"i",NULL))
                report[@"manager_init_error"]=@(((int (*)(id,SEL))objc_msgSend)(cls,initError));
            report[@"manager_available"]=booleanValue(manager,@"available") ?: @NO;
            report[@"bluetooth_enabled"]=booleanValue(manager,@"enabled") ?: @NO;
            report[@"bluetooth_powered"]=booleanValue(manager,@"powered") ?: @NO;
            id devices=objectValue(manager,@"pairedDevices");
            if (![devices isKindOfClass:NSArray.class])
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Paired device list unavailable." userInfo:nil];
            report[@"paired_device_count"]=@([devices count]);
            report[@"device_methods"]=methods(NSClassFromString(@"BluetoothDevice"));
            NSMutableArray *matches=[NSMutableArray new];
            for (id device in devices) {
                id name=objectValue(device,@"name");
                if ([name isKindOfClass:NSString.class] && [name caseInsensitiveCompare:@"Mi True Wireless EBs Basic 2"]==NSOrderedSame)
                    [matches addObject:device];
            }
            report[@"matching_paired_devices"]=@(matches.count);
            if (matches.count!=1)
                @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Exactly one already-paired Mi earbuds entry is required." userInfo:nil];
            id target=matches.firstObject;
            report[@"target_name"]=objectValue(target,@"name");
            NSNumber *connected=booleanValue(target,@"connected");
            if (!connected) @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Connected-state ABI unavailable." userInfo:nil];
            report[@"iphone_connected_before"]=connected;
            if (connect) {
                if (![report[@"bluetooth_enabled"] boolValue] || connected.boolValue)
                    @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Bluetooth must be enabled and the earbuds disconnected from the iPhone." userInfo:nil];
                SEL selector=NSSelectorFromString(@"connectDevice:");
                if (!signature(cls,selector,NO,"v","@"))
                    @throw [NSException exceptionWithName:@"ProbeGuard" reason:@"Connection-request ABI mismatch." userInfo:nil];
                report[@"request_time"]=@(NSDate.date.timeIntervalSince1970);
                ((void (*)(id,SEL,id))objc_msgSend)(manager,selector,target);
                report[@"request_submitted"]=@YES;report[@"connection_requests"]=@1;
                pump(12);
                report[@"iphone_connected_after"]=booleanValue(target,@"connected") ?: @NO;
            }
        } @catch (NSException *exception) { report[@"error"]=exception.reason ?: @"Probe exception."; }
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        if (!json) return 1;
        fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
        return report[@"error"] ? 1 : 0;
    }
}
