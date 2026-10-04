#import "NWBTBridge.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>

static NSString *machine(void) {
    char value[128] = {0}; size_t size = sizeof(value);
    return sysctlbyname("hw.machine", value, &size, NULL, 0) == 0 ?
        [NSString stringWithUTF8String:value] ?: @"unknown" : @"unknown";
}
static BOOL relevant(NSString *selector) {
    NSString *lower = selector.lowercaseString;
    for (NSString *word in @[@"l2cap", @"echo", @"ping", @"rawpacket", @"hcicommand", @"transport"])
        if ([lower containsString:word]) return YES;
    return NO;
}
static NSArray *methods(Class cls) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSNumber *meta in @[@NO, @YES]) {
        unsigned int count = 0;
        Method *list = class_copyMethodList(meta.boolValue ? object_getClass(cls) : cls, &count);
        for (unsigned int index = 0; index < count; ++index) {
            NSString *name = NSStringFromSelector(method_getName(list[index]));
            if (!relevant(name)) continue;
            const char *encoding = method_getTypeEncoding(list[index]);
            [result addObject:@{@"selector": name, @"class_method": meta,
                @"encoding": encoding ? [NSString stringWithUTF8String:encoding] : @""}];
        }
        free(list);
    }
    return result;
}
NSDictionary<NSString *, id> *NWBTInspectTransport(void) {
    @autoreleasepool {
        NSMutableArray *libraries = [NSMutableArray new];
        // Names observed in BlueTool and bluetoothd from the user's iOS 16.3.1.
        NSArray *symbols = @[@"AppleConvergedTransportInitParameters", @"AppleConvergedTransportCreate",
            @"AppleConvergedTransportRead", @"AppleConvergedTransportWrite", @"AppleConvergedTransportFree",
            @"AppleConvergedTransportIsValid", @"AppleConvergedTransportRegisterEventBlockQ"];
        for (NSString *path in @[@"/usr/lib/AppleConvergedTransport.dylib",
                @"/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth",
                @"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager"]) {
            dlerror(); void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
            const char *error = handle ? NULL : dlerror();
            NSMutableDictionary *entry = [@{@"path": path, @"loaded": @(handle != NULL)} mutableCopy];
            if (error) entry[@"error"] = [NSString stringWithUTF8String:error] ?: @"dlopen failed";
            if (handle && [path hasSuffix:@"AppleConvergedTransport.dylib"]) {
                NSMutableDictionary *exports = [NSMutableDictionary new];
                for (NSString *symbol in symbols) exports[symbol] = @(dlsym(handle, symbol.UTF8String) != NULL);
                entry[@"exports"] = exports;
                entry[@"signatures_verified"] = @NO;
            }
            [libraries addObject:entry];
            // Keep handles until this short-lived inspector process exits.
        }
        unsigned int count = 0; Class *classes = objc_copyClassList(&count);
        NSMutableArray *metadata = [NSMutableArray new];
        for (unsigned int index = 0; index < count; ++index) {
            NSString *name = NSStringFromClass(classes[index]);
            if (![name hasPrefix:@"CB"] && ![name hasPrefix:@"Bluetooth"] && ![name hasPrefix:@"BT"]) continue;
            NSArray *candidates = methods(classes[index]);
            if (candidates.count) [metadata addObject:@{@"class": name, @"methods": candidates}];
        }
        free(classes);
        [metadata sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"class"] compare:b[@"class"]];
        }];
        NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
        return @{@"module": @"NukeWireless Bluetooth Bridge", @"version": @"0.0.1~inspect1",
            @"ios": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion],
            @"machine": machine(), @"libraries": libraries, @"method_metadata": metadata,
            @"l2ping_implemented": @NO, @"bluetooth_packets_sent": @0};
    }
}
