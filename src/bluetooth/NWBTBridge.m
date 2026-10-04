#import "NWBTBridge.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <mach-o/loader.h>
#import <ptrauth.h>
#include <string.h>

static NSArray<NSString *> *transportSymbols(void) {
    return @[@"AppleConvergedTransportInitParameters", @"AppleConvergedTransportCreate",
        @"AppleConvergedTransportRead", @"AppleConvergedTransportWrite", @"AppleConvergedTransportFree",
        @"AppleConvergedTransportIsValid", @"AppleConvergedTransportRegisterEventBlockQ"];
}

NSDictionary<NSString *, id> *NWBTCopyTransportCode(void) {
    // Copies bounded code and constant sections of this fixed system library. It never
    // executes its private exports, changes page protections or opens drivers.
    void *handle = dlopen("/usr/lib/AppleConvergedTransport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return @{@"error": @"AppleConvergedTransport could not be loaded"};
    void *symbol = dlsym(handle, "AppleConvergedTransportInitParameters");
    Dl_info image = {0};
    if (!symbol || !dladdr(symbol, &image) || !image.dli_fbase)
        return @{@"error": @"Transport image could not be identified"};
    const struct mach_header_64 *header = image.dli_fbase;
    if (header->magic != MH_MAGIC_64 || header->ncmds > 1024 || header->sizeofcmds > 65536)
        return @{@"error": @"Unsupported transport Mach-O header"};
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t index = 0; index < header->ncmds; ++index) {
        if ((size_t)(end - cursor) < sizeof(struct load_command)) break;
        const struct load_command *command = (const void *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) break;
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const void *)cursor;
            if (!strncmp(segment->segname, "__TEXT", 16) && segment->nsects <=
                    (command->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) {
                const struct section_64 *sections = (const void *)(segment + 1);
                NSMutableArray *constants = [NSMutableArray new];
                for (uint32_t item = 0; item < segment->nsects; ++item) {
                    const struct section_64 *constant = &sections[item];
                    if (strncmp(constant->sectname, "__cstring", 16) && strncmp(constant->sectname, "__const", 16)) continue;
                    if (!(segment->initprot & 1) || constant->addr < segment->vmaddr ||
                        constant->size > 1024 * 1024 || constant->size > segment->vmsize ||
                        constant->addr - segment->vmaddr > segment->vmsize - constant->size)
                        return @{@"error": @"Transport constant section exceeds snapshot bounds"};
                    NSData *value = [NSData dataWithBytes:(const uint8_t *)header + (constant->addr - segment->vmaddr)
                        length:(NSUInteger)constant->size];
                    [constants addObject:@{@"section": [NSString stringWithUTF8String:constant->sectname],
                        @"virtual_address": @(constant->addr), @"size": @(constant->size),
                        @"data_base64": [value base64EncodedStringWithOptions:0]}];
                }
                for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; ++sectionIndex) {
                    const struct section_64 *section = &sections[sectionIndex];
                    if (strncmp(section->sectname, "__text", 16)) continue;
                    if (!(segment->initprot & 1) || section->addr < segment->vmaddr ||
                        section->size > 2 * 1024 * 1024 || section->size > segment->vmsize ||
                        section->addr - segment->vmaddr > segment->vmsize - section->size)
                        return @{@"error": @"Transport code section exceeds snapshot bounds"};
                    const uint8_t *bytes = (const uint8_t *)header + (section->addr - segment->vmaddr);
                    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)section->size];
                    NSMutableDictionary *exports = [NSMutableDictionary new];
                    for (NSString *name in transportSymbols()) {
                        void *address = dlsym(handle, name.UTF8String);
                        uintptr_t pointer = (uintptr_t)ptrauth_strip(address, ptrauth_key_function_pointer);
                        uintptr_t base = (uintptr_t)bytes;
                        if (pointer >= base && pointer - base < section->size)
                            exports[name] = @(section->addr + pointer - base);
                    }
                    return @{@"module": @"NukeWireless Bluetooth Bridge", @"version": NWBT_VERSION,
                        @"image": image.dli_fname ? [NSString stringWithUTF8String:image.dli_fname] : @"unknown",
                        @"section": @"__TEXT.__text", @"virtual_address": @(section->addr),
                        @"size": @(section->size), @"exports": exports, @"constant_sections": constants,
                        @"code_base64": [data base64EncodedStringWithOptions:0],
                        @"bluetooth_packets_sent": @0, @"private_functions_called": @0};
                }
            }
        }
        cursor += command->cmdsize;
    }
    return @{@"error": @"Transport code section not found"};
}

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
        NSArray *symbols = transportSymbols();
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
        return @{@"module": @"NukeWireless Bluetooth Bridge", @"version": NWBT_VERSION,
            @"ios": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion],
            @"machine": machine(), @"libraries": libraries, @"method_metadata": metadata,
            @"l2ping_implemented": @YES, @"l2ping_verified": @NO, @"bluetooth_packets_sent": @0};
    }
}
