// Passive research helper. No manager/advertiser is instantiated, no driver is
// opened, and no HCI command or radio packet is submitted.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <string.h>

int main(void) {
    @autoreleasepool {
        NSMutableArray *libraries = [NSMutableArray new];
        for (NSString *path in @[@"/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth",
            @"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager"]) {
            void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
            [libraries addObject:@{@"path": path, @"loaded": @(handle != NULL)}];
        }
        NSMutableArray *classes = [NSMutableArray new];
        for (NSString *name in @[@"CBAdvertiser", @"CBAdvertiseData", @"CBController", @"CBPeripheralManager", @"BluetoothManager"]) {
            Class cls = NSClassFromString(name);
            NSMutableDictionary *record = [@{@"class": name, @"available": @(cls != Nil)} mutableCopy];
            if (cls) {
                const char *imageName = class_getImageName(cls);
                record[@"image"] = imageName ? [NSString stringWithUTF8String:imageName] : @"";
                NSMutableArray *methods = [NSMutableArray new], *properties = [NSMutableArray new];
                for (NSNumber *meta in @[@NO, @YES]) {
                    unsigned count = 0;
                    Method *list = class_copyMethodList(meta.boolValue ? object_getClass(cls) : cls, &count);
                    for (unsigned i = 0; i < count; ++i) {
                        const char *encoding = method_getTypeEncoding(list[i]);
                        [methods addObject:@{@"selector": NSStringFromSelector(method_getName(list[i])),
                            @"encoding": encoding ? [NSString stringWithUTF8String:encoding] : @"",
                            @"class_method": meta}];
                    }
                    free(list);
                }
                unsigned count = 0;
                objc_property_t *list = class_copyPropertyList(cls, &count);
                for (unsigned i = 0; i < count; ++i) {
                    const char *attributes = property_getAttributes(list[i]);
                    [properties addObject:@{@"name": [NSString stringWithUTF8String:property_getName(list[i])],
                        @"attributes": attributes ? [NSString stringWithUTF8String:attributes] : @""}];
                }
                free(list); record[@"methods"] = methods; record[@"properties"] = properties;
            }
            [classes addObject:record];
        }
        char machine[128] = {0}; size_t length = sizeof(machine);
        sysctlbyname("hw.machine", machine, &length, NULL, 0);
        NSDictionary *report = @{@"tool": @"NWBLEMetadata-1", @"ios": NSProcessInfo.processInfo.operatingSystemVersionString,
            @"machine": [NSString stringWithUTF8String:machine] ?: @"unknown", @"libraries": libraries,
            @"classes": classes, @"driver_channels_opened": @0, @"hci_commands_submitted": @0,
            @"advertisers_created": @0, @"bluetooth_state_modified": @NO};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        if (!json) return 1;
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        return 0;
    }
}
