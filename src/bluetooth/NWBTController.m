#import "NWBTBridge.h"
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
