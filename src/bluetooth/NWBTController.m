#import "NWBTBridge.h"
#import "NWBTNative.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stddef.h>
#include <time.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <mach/mach.h>
#include <uuid/uuid.h>
#include <stdio.h>
#include <poll.h>

// Declarations from Apple IOKitUser/IOKitLib.h and XNU 8792.61.2
// bsd/skywalk/channel/os_channel.h. BlueTool on 20D67 opens port 0
// with os_channel_create(uuid, 0), then reads these channel attributes.
typedef CFMutableDictionaryRef (*NWMatching)(const char *);
typedef kern_return_t (*NWServices)(mach_port_t, CFDictionaryRef, mach_port_t *);
typedef mach_port_t (*NWNext)(mach_port_t);
typedef kern_return_t (*NWIORelease)(mach_port_t);
typedef CFTypeRef (*NWProperty)(mach_port_t, CFStringRef, CFAllocatorRef, uint32_t);
typedef CFTypeRef (*NWSearch)(mach_port_t, const char *, CFStringRef, CFAllocatorRef, uint32_t);
typedef void *(*NWChannelCreate)(const uuid_t, uint32_t);
typedef void (*NWChannelDestroy)(void *);
typedef void *(*NWAttrCreate)(void);
typedef void (*NWAttrDestroy)(void *);
typedef int (*NWAttrRead)(void *, void *);
typedef int (*NWAttrGet)(void *, int, uint64_t *);
typedef struct {
    uint16_t flags, length;
    uint32_t index;
    uint64_t externalPointer, bufferPointer, metadataPointer;
    uint32_t reserved[8];
} NWSlotProperties;
_Static_assert(sizeof(NWSlotProperties) == 64, "Skywalk slot property size");
_Static_assert(offsetof(NWSlotProperties, bufferPointer) == 16, "Skywalk buffer offset");
typedef uint32_t (*NWRingID)(void *, int);
typedef void *(*NWRing)(void *, uint32_t);
typedef void *(*NWSlot)(void *, void *, NWSlotProperties *);
typedef void (*NWSetSlot)(void *, void *, const NWSlotProperties *);
typedef int (*NWAdvance)(void *, void *);
typedef int (*NWSync)(void *, int);
typedef int (*NWChannelFD)(void *);

// Reconstructed from the user's iOS 16.3.1 (20D67) transport code and
// bluetoothd callsites/block signatures. No ABI fallback on other builds.
typedef struct {
    uint32_t type, reserved04;
    void *queue;
    void *stateBlock; // v28@?0i8^v12^v20
    uint32_t timeoutMs, reserved1c, flags, reserved24, reserved28, reserved2c;
    void *writeBlock, *readBlock, *otherBlock, *queue48;
    uint32_t qos, reserved54;
} NWACTParameters;
_Static_assert(sizeof(NWACTParameters) == 0x58, "ACT parameter size");
_Static_assert(offsetof(NWACTParameters, stateBlock) == 0x10, "ACT state block offset");
_Static_assert(offsetof(NWACTParameters, flags) == 0x20, "ACT flags offset");
_Static_assert(offsetof(NWACTParameters, qos) == 0x50, "ACT QoS offset");
typedef void (*NWACTInit)(NWACTParameters *);
typedef bool (*NWACTCreate)(const NWACTParameters *, uint64_t *);
typedef bool (*NWACTFree)(uint64_t *);
typedef bool (*NWACTTransfer)(uint64_t, void *, uint32_t, uint32_t *, uint32_t, void (*)(void *));

static NSDictionary *failure(NSString *stage, NSString *message) {
    return @{@"version": NWBT_VERSION, @"stage": stage, @"error": message,
        @"l2ping_verified": @NO, @"remote_bluetooth_packets_sent": @0};
}

static NSDictionary *requireKnownABI(void) {
    NSDictionary *information = NWBTInspectTransport();
    if (![information[@"machine"] isEqual:@"iPhone11,2"] || ![information[@"ios"] isEqual:@"16.3.1"])
        return failure(@"abi", @"This experimental transport is restricted to iPhone XS / iOS 16.3.1.");
    NSDictionary *snapshot = NWBTCopyTransportCode();
    NSData *code = [[NSData alloc] initWithBase64EncodedString:snapshot[@"code_base64"] ?: @"" options:0];
    if (!code.length || code.length > UINT32_MAX) return failure(@"abi", @"Transport code could not be checked.");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(code.bytes, (CC_LONG)code.length, digest);
    NSMutableString *hash = [NSMutableString new];
    for (NSUInteger index = 0; index < sizeof(digest); ++index) [hash appendFormat:@"%02x", digest[index]];
    if (![hash isEqual:@"16278d023790c1d38a796b31b7c52d4a105916fa7b9be6995b0ec5e3cf91ffed"])
        return failure(@"abi", @"The system transport differs from the inspected ABI. Private calls are disabled.");
    return nil;
}

static NSDictionary *requireBluetoothOff(void) {
    Class manager = NSClassFromString(@"BluetoothManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), enabled = NSSelectorFromString(@"enabled");
    Method factory = class_getClassMethod(manager, shared), getter = class_getInstanceMethod(manager, enabled);
    char factoryType[8] = {0}, getterType[8] = {0};
    if (!factory || !getter || method_getNumberOfArguments(factory) != 2 || method_getNumberOfArguments(getter) != 2)
        return failure(@"bluetooth_state", @"The Bluetooth power state getter is unavailable.");
    method_getReturnType(factory, factoryType, sizeof(factoryType));
    method_getReturnType(getter, getterType, sizeof(getterType));
    if (strcmp(factoryType, "@") || (strcmp(getterType, "B") && strcmp(getterType, "c")))
        return failure(@"bluetooth_state", @"The Bluetooth power state getter ABI is unsupported.");
    id instance = ((id (*)(id, SEL))objc_msgSend)(manager, shared);
    if (!instance) return failure(@"bluetooth_state", @"Bluetooth power state could not be obtained.");
    if (((BOOL (*)(id, SEL))objc_msgSend)(instance, enabled))
        return failure(@"bluetooth_state", @"Turn Bluetooth off in Settings before using the exclusive transport.");
    return nil;
}

static NSDictionary *skywalkVersion(void *channel, uint64_t capacity) {
    NWRingID ringID = (NWRingID)dlsym(RTLD_DEFAULT, "os_channel_ring_id");
    NWRing txRing = (NWRing)dlsym(RTLD_DEFAULT, "os_channel_tx_ring");
    NWRing rxRing = (NWRing)dlsym(RTLD_DEFAULT, "os_channel_rx_ring");
    NWSlot nextSlot = (NWSlot)dlsym(RTLD_DEFAULT, "os_channel_get_next_slot");
    NWSetSlot setSlot = (NWSetSlot)dlsym(RTLD_DEFAULT, "os_channel_set_slot_properties");
    NWAdvance advance = (NWAdvance)dlsym(RTLD_DEFAULT, "os_channel_advance_slot");
    NWSync sync = (NWSync)dlsym(RTLD_DEFAULT, "os_channel_sync");
    NWChannelFD descriptor = (NWChannelFD)dlsym(RTLD_DEFAULT, "os_channel_get_fd");
    if (!ringID || !txRing || !rxRing || !nextSlot || !setSlot || !advance || !sync || !descriptor)
        return failure(@"skywalk_symbols", @"Required channel transfer interfaces are unavailable.");
    if (capacity < 3 || capacity > UINT16_MAX)
        return failure(@"skywalk_capacity", @"The channel buffer size is outside the inspected bounds.");
    void *tx = txRing(channel, ringID(channel, 0));
    void *rx = rxRing(channel, ringID(channel, 2));
    int fd = descriptor(channel);
    if (!tx || !rx || fd < 0) return failure(@"skywalk_rings", @"HCI rings or descriptor are unavailable.");
    // Discard only pre-existing local HCI events before submitting the query.
    // A bounded drain prevents an old version response from counting as new.
    if (sync(channel, 1)) return failure(@"skywalk_drain", @"RX synchronization failed before the query.");
    NSUInteger drained = 0;
    for (; drained < 32; ++drained) {
        NWSlotProperties properties = {0};
        void *slot = nextSlot(rx, NULL, &properties);
        if (!slot) break;
        if (advance(rx, slot)) return failure(@"skywalk_drain", @"A pre-existing RX slot could not be released.");
    }
    if (drained == 32 || sync(channel, 1))
        return failure(@"skywalk_drain", @"Pre-existing events exceeded the bounded drain.");
    NWSlotProperties properties = {0};
    void *slot = nextSlot(tx, NULL, &properties);
    uint8_t command[] = {0x01, 0x10, 0x00}; // HCI 0x1001; no H4 prefix on Skywalk.
    if (!slot || !properties.bufferPointer || properties.length < sizeof(command) || properties.length > capacity)
        return failure(@"skywalk_tx", @"No TX slot with the inspected capacity is available.");
    // BlueTool's 0x100005414 wrapper removes its one-byte H4 prefix before
    // 0x100005428 writes to this ring. Preserve all immutable slot fields.
    memcpy((void *)(uintptr_t)properties.bufferPointer, command, sizeof(command));
    properties.length = sizeof(command);
    setSlot(tx, slot, &properties);
    if (advance(tx, slot)) return failure(@"skywalk_tx", @"The command slot could not be committed.");
    fputs("NWBT phase: local version command submitted\n", stderr);
    NSDictionary *result = nil;
    if (sync(channel, 0)) result = failure(@"skywalk_tx", @"TX synchronization failed after command submission.");
    NSMutableData *events = [NSMutableData new];
    NSMutableArray *eventCodes = [NSMutableArray new];
    NSUInteger slotsRead = 0, totalBytes = 0;
    double deadline = NSProcessInfo.processInfo.systemUptime + 3.0;
    while (!result && NSProcessInfo.processInfo.systemUptime < deadline) {
        if (sync(channel, 1)) { result = failure(@"skywalk_rx", @"RX synchronization failed."); break; }
        NWSlotProperties received = {0};
        void *rxSlot = nextSlot(rx, NULL, &received);
        if (!rxSlot) {
            struct pollfd waitFD = {.fd = fd, .events = POLLIN};
            int ready = poll(&waitFD, 1, 50);
            if (ready < 0 && errno != EINTR) result = failure(@"skywalk_rx", @"Polling the HCI descriptor failed.");
            else if (ready > 0 && (waitFD.revents & (POLLERR | POLLHUP | POLLNVAL)))
                result = failure(@"skywalk_rx", @"The HCI descriptor reported a terminal condition.");
            continue;
        }
        if (!received.bufferPointer || !received.length || received.length > capacity ||
            ++slotsRead > 128 || totalBytes + received.length > 8192) {
            result = failure(@"skywalk_rx", @"RX data exceeded the bounded slot or stream limits.");
            break;
        }
        [events appendBytes:(const void *)(uintptr_t)received.bufferPointer length:received.length];
        totalBytes += received.length;
        if (advance(rx, rxSlot)) { result = failure(@"skywalk_rx", @"The received slot could not be released."); break; }
        while (events.length >= 2 && !result) {
            const uint8_t *packet = events.bytes;
            NSUInteger length = (NSUInteger)packet[1] + 2;
            if (events.length < length) break;
            if (eventCodes.count < 16) [eventCodes addObject:@(packet[0])];
            if (packet[0] == 0x0e && length >= 14 && packet[3] == 0x01 && packet[4] == 0x10) {
                if (packet[5]) result = failure(@"hci_response", [NSString stringWithFormat:@"HCI status 0x%02x.", packet[5]]);
                else result = @{@"version": NWBT_VERSION, @"stage": @"controller_ready",
                    @"hci_version": @(packet[6]), @"hci_revision": @(packet[7] | packet[8] << 8),
                    @"lmp_version": @(packet[9]), @"manufacturer": @(packet[10] | packet[11] << 8),
                    @"lmp_subversion": @(packet[12] | packet[13] << 8),
                    @"remote_bluetooth_packets_sent": @0, @"l2ping_verified": @NO};
            }
            [events replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
        }
    }
    if (!result) result = failure(@"skywalk_rx", @"No matching local version response arrived within three seconds.");
    NSMutableDictionary *details = [result mutableCopy];
    details[@"local_hci_commands_submitted"] = @1;
    details[@"rx_slots_consumed"] = @(slotsRead);
    details[@"event_codes"] = eventCodes;
    return details;
}

NSDictionary *NWBTNativeGuard(void) {
    if (getuid() != 0) return failure(@"permissions", @"Run this exclusive diagnostic as root.");
    fputs("NWBT phase: ABI guard\n", stderr);
    NSDictionary *error = requireKnownABI();
    if (error) return error;
    fputs("NWBT phase: Bluetooth state\n", stderr);
    error = requireBluetoothOff();
    if (error) return error;
    return nil;
}

static void *nativeOpenFailure(NSDictionary **error, NSDictionary *report) { *error = report; return NULL; }

void *NWBTOpenNativeChannel(NSString *wanted, uint64_t *capacity, NSDictionary **error) {
    fputs("NWBT phase: registry lookup\n", stderr);
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    NWMatching matching = (NWMatching)dlsym(iokit, "IOServiceMatching");
    NWServices services = (NWServices)dlsym(iokit, "IOServiceGetMatchingServices");
    NWNext next = (NWNext)dlsym(iokit, "IOIteratorNext");
    NWIORelease release = (NWIORelease)dlsym(iokit, "IOObjectRelease");
    NWProperty property = (NWProperty)dlsym(iokit, "IORegistryEntryCreateCFProperty");
    NWSearch search = (NWSearch)dlsym(iokit, "IORegistryEntrySearchCFProperty");
    NWChannelCreate create = (NWChannelCreate)dlsym(RTLD_DEFAULT, "os_channel_create");
    NWChannelDestroy destroy = (NWChannelDestroy)dlsym(RTLD_DEFAULT, "os_channel_destroy");
    NWAttrCreate attrCreate = (NWAttrCreate)dlsym(RTLD_DEFAULT, "os_channel_attr_create");
    NWAttrDestroy attrDestroy = (NWAttrDestroy)dlsym(RTLD_DEFAULT, "os_channel_attr_destroy");
    NWAttrRead attrRead = (NWAttrRead)dlsym(RTLD_DEFAULT, "os_channel_read_attr");
    NWAttrGet attrGet = (NWAttrGet)dlsym(RTLD_DEFAULT, "os_channel_attr_get");
    if (!iokit || !matching || !services || !next || !release || !property || !search ||
        !create || !destroy || !attrCreate || !attrDestroy || !attrRead || !attrGet)
        return nativeOpenFailure(error, failure(@"skywalk_symbols", @"The inspected IOKit/Skywalk interfaces are unavailable."));
    CFMutableDictionaryRef match = matching("AppleConvergedIPCRTIInterface");
    if (!match) return nativeOpenFailure(error, failure(@"skywalk_registry", @"The HCI registry matching dictionary could not be created."));
    mach_port_t iterator = MACH_PORT_NULL;
    kern_return_t status = services(MACH_PORT_NULL, match, &iterator); // Consumes match.
    if (status || !iterator) {
        if (iterator) release(iterator);
        return nativeOpenFailure(error, failure(@"skywalk_registry", [NSString stringWithFormat:@"Interface lookup failed: 0x%08x.", status]));
    }
    NSString *identifier = nil;
    NSUInteger candidates = 0;
    mach_port_t entry;
    while (candidates++ < 64 && (entry = next(iterator))) {
        id protocol = CFBridgingRelease(property(entry, CFSTR("ACIPCInterfaceProtocol"), kCFAllocatorDefault, 0));
        id transport = CFBridgingRelease(property(entry, CFSTR("ACIPCInterfaceTransport"), kCFAllocatorDefault, 0));
        if ([protocol isKindOfClass:NSString.class] && [protocol isEqual:wanted] &&
            [transport isKindOfClass:NSString.class] && [transport isEqual:@"skywalk"]) {
            id value = CFBridgingRelease(search(entry, "IOService", CFSTR("IOSkywalkNexusUUID"), kCFAllocatorDefault, 1));
            if ([value isKindOfClass:NSString.class]) identifier = value;
        }
        release(entry);
        if (identifier) break;
    }
    release(iterator);
    uuid_t uuid;
    if (!identifier || uuid_parse(identifier.UTF8String, uuid))
        return nativeOpenFailure(error, failure(@"skywalk_registry", @"No valid nexus identifier was found under the HCI interface."));
    errno = 0;
    fputs("NWBT phase: channel open\n", stderr);
    void *channel = create(uuid, 0);
    fputs("NWBT phase: channel open returned\n", stderr);
    if (!channel) {
        int savedErrno = errno;
        NSMutableDictionary *report = [failure(@"skywalk_open", @"The native HCI Skywalk channel could not be opened.") mutableCopy];
        report[@"system_errno"] = @(savedErrno);
        report[@"system_error"] = [NSString stringWithUTF8String:strerror(savedErrno)];
        *error = report; return NULL;
    }
    void *attributes = attrCreate();
    if (!attributes) { destroy(channel); return nativeOpenFailure(error, failure(@"skywalk_attributes", @"No channel attributes.")); }
    uint64_t bytes = 0;
    int result = attrRead(channel, attributes) || attrGet(attributes, 4, &bytes);
    attrDestroy(attributes);
    if (result || bytes < 20 || bytes > UINT16_MAX) {
        destroy(channel); return nativeOpenFailure(error, failure(@"skywalk_attributes", @"Invalid channel capacity."));
    }
    *capacity = bytes;
    return channel;
}

void NWBTCloseNativeChannel(void *channel) {
    NWChannelDestroy destroy = (NWChannelDestroy)dlsym(RTLD_DEFAULT, "os_channel_destroy");
    if (channel && destroy) destroy(channel);
}

static NSDictionary *skywalkDiagnostic(BOOL queryController) {
    NSDictionary *error = NWBTNativeGuard();
    if (error) return error;
    uint64_t capacity = 0;
    void *channel = NWBTOpenNativeChannel(@"hci", &capacity, &error);
    if (!channel) return error;
    @try {
        return queryController ? skywalkVersion(channel, capacity) :
            @{@"version": NWBT_VERSION, @"stage": @"skywalk_opened", @"slot_buffer_size": @(capacity),
              @"remote_bluetooth_packets_sent": @0, @"l2ping_verified": @NO};
    } @finally { NWBTCloseNativeChannel(channel); }
}

NSDictionary<NSString *, id> *NWBTOpenSkywalk(void) { return skywalkDiagnostic(NO); }
NSDictionary<NSString *, id> *NWBTReadSkywalkController(void) { return skywalkDiagnostic(YES); }

NSDictionary<NSString *, id> *NWBTReadControllerInfo(void) {
    @autoreleasepool {
        if (getuid() != 0) return failure(@"permissions", @"Run this exclusive diagnostic as root.");
        NSDictionary *error = requireKnownABI();
        if (error) return error;
        error = requireBluetoothOff();
        if (error) return error;
        void *library = dlopen("/usr/lib/AppleConvergedTransport.dylib", RTLD_LAZY | RTLD_LOCAL);
        NWACTInit initialize = (NWACTInit)dlsym(library, "AppleConvergedTransportInitParameters");
        NWACTCreate create = (NWACTCreate)dlsym(library, "AppleConvergedTransportCreate");
        NWACTFree release = (NWACTFree)dlsym(library, "AppleConvergedTransportFree");
        NWACTTransfer write = (NWACTTransfer)dlsym(library, "AppleConvergedTransportWrite");
        NWACTTransfer read = (NWACTTransfer)dlsym(library, "AppleConvergedTransportRead");
        if (!library || !initialize || !create || !release || !write || !read)
            return failure(@"symbols", @"Required transport functions are unavailable.");
        dispatch_queue_t queue = dispatch_queue_create("com.gokuencinar.nukewireless.bluetooth.controller", DISPATCH_QUEUE_SERIAL);
        void (^stateBlock)(int, void *, void *) = ^(int status, void *argument1, void *argument2) {
            (void)status; (void)argument1; (void)argument2;
        };
        uint64_t hci = 0;
        NSDictionary *result = nil;
        @try {
            NWACTParameters parameters;
            initialize(&parameters);
            if (parameters.qos != 0x15) return failure(@"parameters", @"Unexpected initialized transport parameters.");
            // The actual XS registry exposes hci/sco/acl through OLYBT RTI
            // Skywalk. It has no CBTI device; opening legacy BTI first fails.
            parameters.type = 2; parameters.queue = (__bridge void *)queue;
            parameters.stateBlock = (__bridge void *)stateBlock; parameters.timeoutMs = 1000;
            parameters.flags = 8; // Queue-backed HCI, synchronous transfer (bit 2 clear).
            errno = 0;
            if (!create(&parameters, &hci) || !hci) {
                int savedErrno = errno;
                NSMutableDictionary *details = [failure(@"hci_open", @"The HCI transport could not be opened.") mutableCopy];
                details[@"system_errno"] = @(savedErrno);
                result = details;
            }
            if (!result) {
                // Standard HCI Read Local Version Information. It addresses
                // this controller only, with no remote connection or firmware writes.
                uint8_t command[] = {0x01, 0x10, 0x00}; uint32_t written = 0;
                if (!write(hci, command, sizeof(command), &written, 250, NULL) || written != sizeof(command))
                    result = failure(@"hci_write", @"The controller did not accept Read Local Version Information.");
                else {
                    NSMutableData *events = [NSMutableData new];
                    double deadline = NSProcessInfo.processInfo.systemUptime + 2.0;
                    while (!result && NSProcessInfo.processInfo.systemUptime < deadline) {
                        uint8_t bytes[260]; uint32_t received = 0;
                        bool ok = read(hci, bytes, sizeof(bytes), &received, 100, NULL);
                        if (ok && received && received <= sizeof(bytes)) [events appendBytes:bytes length:received];
                        else { struct timespec pause = {.tv_nsec = 1000000}; nanosleep(&pause, NULL); }
                        if (events.length > 1024) { result = failure(@"hci_read", @"Controller event framing exceeded the bounded buffer."); break; }
                        while (events.length >= 2 && !result) {
                            const uint8_t *packet = events.bytes;
                            NSUInteger frameLength = (NSUInteger)packet[1] + 2;
                            if (events.length < frameLength) break;
                            if (packet[0] == 0x0e && frameLength >= 14 && packet[3] == 0x01 && packet[4] == 0x10) {
                                if (packet[5]) result = failure(@"hci_response", [NSString stringWithFormat:@"The controller returned HCI status 0x%02x.", packet[5]]);
                                else result = @{@"version": NWBT_VERSION, @"stage": @"controller_ready",
                                    @"hci_version": @(packet[6]), @"hci_revision": @(packet[7] | packet[8] << 8),
                                    @"manufacturer": @(packet[10] | packet[11] << 8),
                                    @"lmp_subversion": @(packet[12] | packet[13] << 8),
                                    @"local_hci_commands_sent": @1, @"remote_bluetooth_packets_sent": @0,
                                    @"l2ping_verified": @NO};
                            }
                            [events replaceBytesInRange:NSMakeRange(0, frameLength) withBytes:NULL length:0];
                        }
                    }
                    if (!result) result = failure(@"hci_read", @"No matching controller version response arrived within two seconds.");
                }
            }
        } @finally {
            if (hci) release(&hci);
        }
        return result;
    }
}
