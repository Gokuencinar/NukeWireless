// Passive research helper. No manager/advertiser is instantiated, no driver is
// opened, and no HCI command or radio packet is submitted.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

static id objectGetter(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    char result[64] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, result, sizeof result);
    if (result[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSDictionary *registration(void) {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    Method method = class_getClassMethod(proxyClass, selector);
    char result[64] = {0}, argument[64] = {0};
    if (method) {
        method_getReturnType(method, result, sizeof result);
        method_getArgumentType(method, 2, argument, sizeof argument);
    }
    if (!method || method_getNumberOfArguments(method) != 3 || result[0] != '@' || argument[0] != '@')
        return @{@"available": @NO};
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, selector, @"me.midnightchips.harpy-reloaded");
    NSMutableDictionary *record = [@{@"available": @(proxy != nil)} mutableCopy];
    for (NSString *key in @[@"applicationIdentifier", @"applicationType", @"bundleURL", @"canonicalExecutablePath", @"shortVersionString"]) {
        id value = objectGetter(proxy, key);
        if (value) record[key] = [value description];
    }
    return record;
}

static NSArray *authorizationRows(void) {
    NSMutableArray *databases = [NSMutableArray new];
    for (NSString *path in @[@"/rootfs/var/mobile/Library/TCC/TCC.db", @"/var/mobile/Library/TCC/TCC.db"]) {
        sqlite3 *database = NULL;
        int status = sqlite3_open_v2(path.UTF8String, &database, SQLITE_OPEN_READONLY, NULL);
        NSMutableDictionary *record = [@{@"path": path, @"open_status": @(status)} mutableCopy];
        if (status == SQLITE_OK) {
            sqlite3_busy_timeout(database, 500);
            const char *sql = "SELECT service,client,auth_value,auth_reason FROM access "
                "WHERE service IN ('kTCCServiceBluetoothAlways','kTCCServiceBluetoothPeripheral') "
                "AND (client='me.midnightchips.harpy-reloaded' OR client LIKE '%/HarpyReloaded.app/HarpyReloaded') LIMIT 8";
            sqlite3_stmt *statement = NULL;
            status = sqlite3_prepare_v2(database, sql, -1, &statement, NULL);
            record[@"query_status"] = @(status);
            NSMutableArray *rows = [NSMutableArray new];
            if (status == SQLITE_OK) {
                while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
                    const unsigned char *service = sqlite3_column_text(statement, 0);
                    const unsigned char *client = sqlite3_column_text(statement, 1);
                    [rows addObject:@{@"service": service ? [NSString stringWithUTF8String:(const char *)service] : @"",
                        @"client": client ? [NSString stringWithUTF8String:(const char *)client] : @"",
                        @"auth_value": @(sqlite3_column_int(statement, 2)), @"auth_reason": @(sqlite3_column_int(statement, 3))}];
                }
                record[@"step_status"] = @(status);
            }
            record[@"rows"] = rows;
            sqlite3_finalize(statement);
        }
        if (database) sqlite3_close(database);
        [databases addObject:record];
    }
    return databases;
}

int main(void) {
    @autoreleasepool {
        NSMutableArray *libraries = [NSMutableArray new];
        for (NSString *path in @[@"/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth",
            @"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",
            @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices"]) {
            void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
            [libraries addObject:@{@"path": path, @"loaded": @(handle != NULL)}];
        }
        NSMutableArray *classes = [NSMutableArray new];
        for (NSString *name in @[@"CBManager", @"CBCentralManager", @"CBAdvertiser", @"CBAdvertiseData", @"CBController", @"CBPeripheralManager", @"BluetoothManager"]) {
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
        NSDictionary *report = @{@"tool": @"NWBLEMetadata-2", @"ios": NSProcessInfo.processInfo.operatingSystemVersionString,
            @"machine": [NSString stringWithUTF8String:machine] ?: @"unknown", @"libraries": libraries,
            @"classes": classes, @"app_registration": registration(), @"app_bluetooth_authorization_rows": authorizationRows(),
            @"driver_channels_opened": @0, @"hci_commands_submitted": @0,
            @"advertisers_created": @0, @"bluetooth_state_modified": @NO};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        if (!json) return 1;
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        return 0;
    }
}
