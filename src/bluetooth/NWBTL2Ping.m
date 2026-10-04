#import "NWBTBridge.h"
#import "NWBTNative.h"
#include <dlfcn.h>
#include <poll.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>

volatile sig_atomic_t NWBTCancelled = 0;
static double now(void) { return NSProcessInfo.processInfo.systemUptime; }
static uint16_t u16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static void put16(uint8_t *p, uint16_t value) { p[0] = value; p[1] = value >> 8; }

// Apple XNU 8792.61.2 os_channel.h. Layout also checked against 20D67
// bluetoothd's skywalk_write_channel at 0x100061d80: ACL header is four
// bytes (handle/flags + length), followed by payload, with no H4 prefix.
typedef struct {
    uint16_t flags, length; uint32_t index;
    uint64_t externalPointer, bufferPointer, metadataPointer; uint32_t reserved[8];
} SlotProperties;
_Static_assert(sizeof(SlotProperties) == 64, "Skywalk slot ABI");
_Static_assert(offsetof(SlotProperties, bufferPointer) == 16, "Skywalk buffer ABI");

@interface NWBTRing : NSObject {
    void *_channel, *_tx, *_rx;
    uint64_t _capacity;
    int _fd;
    void *(*_next)(void *, void *, SlotProperties *);
    void (*_set)(void *, void *, const SlotProperties *);
    int (*_advance)(void *, void *);
    int (*_sync)(void *, int);
    NSUInteger _slots, _bytes;
}
@property(nonatomic, copy) NSString *error;
- (instancetype)initWithChannel:(void *)channel capacity:(uint64_t)capacity;
- (BOOL)send:(NSData *)packet;
- (NSData *)read;
- (int)descriptor;
@end

@implementation NWBTRing
- (instancetype)initWithChannel:(void *)channel capacity:(uint64_t)capacity {
    if (!(self = [super init])) return nil;
    uint32_t (*ringID)(void *, int) = dlsym(RTLD_DEFAULT, "os_channel_ring_id");
    void *(*tx)(void *, uint32_t) = dlsym(RTLD_DEFAULT, "os_channel_tx_ring");
    void *(*rx)(void *, uint32_t) = dlsym(RTLD_DEFAULT, "os_channel_rx_ring");
    int (*fd)(void *) = dlsym(RTLD_DEFAULT, "os_channel_get_fd");
    _next = dlsym(RTLD_DEFAULT, "os_channel_get_next_slot");
    _set = dlsym(RTLD_DEFAULT, "os_channel_set_slot_properties");
    _advance = dlsym(RTLD_DEFAULT, "os_channel_advance_slot");
    _sync = dlsym(RTLD_DEFAULT, "os_channel_sync");
    if (!ringID || !tx || !rx || !fd || !_next || !_set || !_advance || !_sync) return nil;
    _channel = channel; _capacity = capacity;
    _tx = tx(channel, ringID(channel, 0)); _rx = rx(channel, ringID(channel, 2)); _fd = fd(channel);
    if (!_tx || !_rx || _fd < 0) return nil;
    return self;
}
- (int)descriptor { return _fd; }
- (BOOL)send:(NSData *)packet {
    if (self.error) return NO;
    SlotProperties properties = {0};
    void *slot = _next(_tx, NULL, &properties);
    if (!slot || !properties.bufferPointer || !packet.length || packet.length > properties.length || properties.length > _capacity) {
        self.error = @"No valid TX slot available."; return NO;
    }
    memcpy((void *)(uintptr_t)properties.bufferPointer, packet.bytes, packet.length);
    properties.length = (uint16_t)packet.length;
    _set(_tx, slot, &properties);
    if (_advance(_tx, slot) || _sync(_channel, 0)) { self.error = @"TX commit failed."; return NO; }
    return YES;
}
- (NSData *)read {
    if (self.error) return nil;
    if (_sync(_channel, 1)) { self.error = @"RX synchronization failed."; return nil; }
    SlotProperties properties = {0};
    void *slot = _next(_rx, NULL, &properties);
    if (!slot) return nil;
    if (!properties.bufferPointer || !properties.length || properties.length > _capacity || ++_slots > 1024 || _bytes + properties.length > 65536) {
        self.error = @"RX exceeded bounded capacity."; return nil;
    }
    NSData *data = [NSData dataWithBytes:(void *)(uintptr_t)properties.bufferPointer length:properties.length];
    _bytes += properties.length;
    if (_advance(_rx, slot)) { self.error = @"RX release failed."; return nil; }
    return data;
}
@end

@interface NWBTPingSession : NSObject
@property(nonatomic, strong) NWBTRing *hci, *acl;
@property(nonatomic, strong) NSData *address;
@property(nonatomic, strong) NSMutableData *events, *aclStream, *pdu;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *completions;
@property(nonatomic, strong) NSMutableArray<NSData *> *auxiliary;
@property(nonatomic, strong) NSMutableArray *samples, *eventCodes;
@property(nonatomic, copy) NSString *error;
@property(nonatomic) uint16_t handle, mtu;
@property(nonatomic) BOOL connected, pending, disconnectConfirmed, cancelConfirmed;
@property(nonatomic) NSUInteger credits, commandCredits, submitted, commands, auxiliarySent;
@property(nonatomic) uint8_t echoID;
@property(nonatomic, strong) NSData *nonce;
@property(nonatomic) double sentAt, rtt;
@property(nonatomic) BOOL echoReceived, echoRejected;
@end

@implementation NWBTPingSession
- (BOOL)command:(uint16_t)opcode parameters:(NSData *)parameters {
    if (!self.commandCredits) { self.error = @"Controller command credit unavailable."; return NO; }
    uint8_t header[3]; put16(header, opcode); header[2] = (uint8_t)parameters.length;
    NSMutableData *command = [NSMutableData dataWithBytes:header length:3];
    [command appendData:parameters];
    [self.completions removeObjectForKey:@(opcode)];
    if (![self.hci send:command]) { self.error = self.hci.error; return NO; }
    self.commandCredits = 0; self.commands++;
    return YES;
}
- (void)event:(NSData *)event {
    const uint8_t *p = event.bytes; NSUInteger length = event.length;
    if (self.eventCodes.count < 64) [self.eventCodes addObject:@(p[0])];
    if (p[0] == 0x0e && length >= 6) {
        self.commandCredits = p[2] ? 1 : 0;
        self.completions[@(u16(p + 3))] = event;
        if (u16(p + 3) == 0x0408 && !p[5]) self.cancelConfirmed = YES;
    } else if (p[0] == 0x0f && length >= 6) {
        self.commandCredits = p[3] ? 1 : 0;
        if (p[2]) self.error = [NSString stringWithFormat:@"Command 0x%04x rejected: HCI 0x%02x.", u16(p + 4), p[2]];
    } else if (p[0] == 0x03 && length == 13 && !memcmp(p + 5, self.address.bytes, 6)) {
        self.pending = NO;
        if (p[2]) self.error = [NSString stringWithFormat:@"Connection failed: HCI 0x%02x.", p[2]];
        else if (p[11] == 1) { self.handle = u16(p + 3) & 0x0fff; self.connected = YES; self.credits = 1; }
        else self.error = @"The returned link is not an ACL connection.";
    } else if (p[0] == 0x05 && length == 6 && self.connected && (u16(p + 3) & 0x0fff) == self.handle && !p[2]) {
        self.connected = NO; self.disconnectConfirmed = YES;
    } else if (p[0] == 0x13 && length >= 3 && length == 3 + (NSUInteger)p[2] * 4) {
        for (NSUInteger i = 0; i < p[2]; ++i)
            if ((u16(p + 3 + i * 4) & 0x0fff) == self.handle && u16(p + 5 + i * 4)) self.credits = 1;
    } else if ((p[0] == 0x16 || p[0] == 0x17 || p[0] == 0x31) && length >= 8 && !memcmp(p + 2, self.address.bytes, 6)) {
        self.error = @"The target requested pairing; this diagnostic does not create or store pairing keys.";
    }
}
- (NSData *)signaling:(uint8_t)code identifier:(uint8_t)identifier payload:(NSData *)payload {
    uint8_t header[12]; put16(header, self.handle | 0x2000); put16(header + 2, (uint16_t)payload.length + 8);
    put16(header + 4, (uint16_t)payload.length + 4); put16(header + 6, 1);
    header[8] = code; header[9] = identifier; put16(header + 10, (uint16_t)payload.length);
    NSMutableData *packet = [NSMutableData dataWithBytes:header length:12]; [packet appendData:payload]; return packet;
}
- (void)signalingPDU:(NSData *)data {
    const uint8_t *p = data.bytes; NSUInteger size = data.length;
    if (size < 4 || u16(p + 2) != 1) return;
    for (NSUInteger offset = 4; offset + 4 <= size;) {
        uint8_t code = p[offset], identifier = p[offset + 1]; NSUInteger length = u16(p + offset + 2);
        if (!identifier || offset + 4 + length > size) { self.error = @"Malformed L2CAP signaling data."; return; }
        if (!self.echoReceived && self.nonce && identifier == self.echoID && code == 9 && length == self.nonce.length && !memcmp(p + offset + 4, self.nonce.bytes, length)) {
            self.echoReceived = YES; self.rtt = (now() - self.sentAt) * 1000;
        } else if (identifier == self.echoID && code == 1 && length >= 2) self.echoRejected = YES;
        else if (code == 0x0a && length == 2 && self.auxiliary.count + self.auxiliarySent < 10) {
            uint16_t type = u16(p + offset + 4); uint8_t reply[8] = {0}; put16(reply, type);
            NSUInteger replySize = 4;
            if (type == 1) { put16(reply + 4, 672); replySize = 6; }
            else if (type == 2) replySize = 8; // No optional L2CAP features advertised.
            else put16(reply + 2, 1);
            [self.auxiliary addObject:[self signaling:0x0b identifier:identifier payload:[NSData dataWithBytes:reply length:replySize]]];
        }
        offset += length + 4;
    }
}
- (void)aclPacket:(NSData *)packet {
    const uint8_t *p = packet.bytes;
    uint16_t header = u16(p); NSUInteger length = u16(p + 2), boundary = (header >> 12) & 3;
    if (!self.connected || (header & 0x0fff) != self.handle || (header & 0xc000)) return;
    if (boundary == 0 || boundary == 2) [self.pdu setLength:0];
    else if (boundary != 1 || !self.pdu.length) return;
    if (self.pdu.length + length > 1024) { self.error = @"L2CAP reassembly exceeded its bound."; return; }
    [self.pdu appendBytes:p + 4 length:length];
    if (self.pdu.length < 4) return;
    NSUInteger required = 4 + u16(self.pdu.bytes);
    if (required > 1024 || self.pdu.length > required) { self.error = @"Invalid L2CAP reassembly length."; return; }
    if (self.pdu.length == required) { [self signalingPDU:self.pdu]; [self.pdu setLength:0]; }
}
- (void)pump {
    for (NSUInteger pass = 0; pass < 16; ++pass) {
        NSData *event = [self.hci read], *acl = [self.acl read];
        if (event) [self.events appendData:event]; if (acl) [self.aclStream appendData:acl];
        if (!event && !acl) break;
        if (self.events.length > 4096 || self.aclStream.length > 4096) { self.error = @"Stream limit exceeded."; return; }
        while (self.events.length >= 2) {
            const uint8_t *p = self.events.bytes; NSUInteger length = p[1] + 2;
            if (self.events.length < length) break;
            [self event:[self.events subdataWithRange:NSMakeRange(0, length)]];
            [self.events replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
        }
        while (self.aclStream.length >= 4) {
            const uint8_t *p = self.aclStream.bytes; NSUInteger length = 4 + u16(p + 2);
            if (length > 1028) { self.error = @"ACL length exceeded its bound."; return; }
            if (self.aclStream.length < length) break;
            [self aclPacket:[self.aclStream subdataWithRange:NSMakeRange(0, length)]];
            [self.aclStream replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
        }
    }
    if (self.hci.error || self.acl.error) self.error = self.hci.error ?: self.acl.error;
    if (self.connected && self.credits && self.auxiliary.count) {
        if ([self.acl send:self.auxiliary.firstObject]) { self.credits = 0; self.auxiliarySent++; [self.auxiliary removeObjectAtIndex:0]; }
        else self.error = self.acl.error;
    }
    struct pollfd descriptors[2] = {{[self.hci descriptor], POLLIN, 0}, {[self.acl descriptor], POLLIN, 0}};
    int result = poll(descriptors, 2, 20);
    if (result < 0 && errno != EINTR) self.error = @"Channel polling failed.";
    for (NSUInteger i = 0; i < 2; ++i)
        if (descriptors[i].revents & (POLLERR | POLLHUP | POLLNVAL)) self.error = @"Channel closed during the diagnostic.";
}
- (NSData *)waitComplete:(uint16_t)opcode deadline:(double)deadline {
    while (now() < deadline && !NWBTCancelled && !self.error && !self.completions[@(opcode)]) [self pump];
    NSData *reply = self.completions[@(opcode)];
    if (!reply && !self.error) self.error = @"No command completion arrived before the deadline.";
    return reply;
}
- (void)cleanup {
    // Cleanup ignores soft cancellation and earlier protocol errors, but stays
    // within three seconds. The caller also has a process watchdog and an
    // independent Bluetooth-service recovery scheduled before exclusive access.
    double deadline = now() + 3.0;
    [self.auxiliary removeAllObjects];
    while (!self.commandCredits && now() < deadline) [self pump];
    if (self.pending && self.commandCredits) [self command:0x0408 parameters:self.address];
    while (self.pending && !self.cancelConfirmed && now() < deadline) [self pump];
    if (self.connected) {
        while (!self.commandCredits && now() < deadline) [self pump];
        uint8_t parameters[3]; put16(parameters, self.handle); parameters[2] = 0x13;
        if (self.commandCredits) [self command:0x0406 parameters:[NSData dataWithBytes:parameters length:3]];
        while (self.connected && now() < deadline) [self pump];
    }
}
@end

NSDictionary<NSString *, id> *NWBTL2Ping(NSString *destination) {
    return NWBTL2PingWithOptions(destination, NWBT_DEFAULT_COUNT, NWBT_DEFAULT_INTERVAL);
}

NSDictionary<NSString *, id> *NWBTL2PingWithOptions(NSString *destination, NSUInteger count, NSUInteger intervalSeconds) {
    if (!NWBTPingOptionsValid(count, intervalSeconds))
        return @{@"version": NWBT_VERSION, @"stage": @"arguments", @"error_code": @"arguments", @"error": @"Invalid bounded ping options."};
    NSMutableDictionary *report = [@{@"version": NWBT_VERSION, @"stage": @"l2ping", @"l2ping_verified": @NO,
        @"requested_count": @(count), @"interval_seconds": @(intervalSeconds)} mutableCopy];
    NSArray *parts = [destination componentsSeparatedByString:@":"]; uint8_t address[6];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    if (parts.count != 6) { report[@"error"] = @"Expected a colon-separated Bluetooth address."; return report; }
    for (NSUInteger i = 0; i < 6; ++i) {
        NSString *part = parts[i];
        if (part.length != 2 || [part rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound) { report[@"error"] = @"Invalid Bluetooth address."; return report; }
        address[5 - i] = (uint8_t)strtoul(part.UTF8String, NULL, 16);
    }
    if (!memcmp(address, "\0\0\0\0\0\0", 6) || !memcmp(address, "\xff\xff\xff\xff\xff\xff", 6)) { report[@"error"] = @"Invalid target address."; return report; }
    NSDictionary *error = NWBTNativeGuard(); if (error) return error;
    uint64_t hciCapacity = 0, aclCapacity = 0;
    void *hci = NWBTOpenNativeChannel(@"hci", &hciCapacity, &error); if (!hci) return error;
    void *acl = NULL; NWBTPingSession *session = [NWBTPingSession new];
    session.address = [NSData dataWithBytes:address length:6]; session.commandCredits = 1;
    session.events = [NSMutableData new]; session.aclStream = [NSMutableData new]; session.pdu = [NSMutableData new];
    session.completions = [NSMutableDictionary new]; session.auxiliary = [NSMutableArray new];
    session.samples = [NSMutableArray new]; session.eventCodes = [NSMutableArray new];
    @try {
        acl = NWBTOpenNativeChannel(@"acl", &aclCapacity, &error);
        if (!acl) return error;
        session.hci = [[NWBTRing alloc] initWithChannel:hci capacity:hciCapacity];
        session.acl = [[NWBTRing alloc] initWithChannel:acl capacity:aclCapacity];
        if (!session.hci || !session.acl) { report[@"error"] = @"Channel transfer interfaces unavailable."; return report; }
        // Drain stale events before any connection command; bounded to 32 slots.
        for (NSUInteger i = 0; i < 32; ++i) {
            NSData *a = [session.hci read], *b = [session.acl read];
            if (!a && !b) break;
            if (i == 31) session.error = @"Pre-existing RX traffic exceeded its bound.";
        }
        if (session.hci.error || session.acl.error) session.error = session.hci.error ?: session.acl.error;
        if (!session.error && [session command:0x1005 parameters:[NSData data]]) {
            NSData *reply = [session waitComplete:0x1005 deadline:now() + 2.0];
            const uint8_t *p = reply.bytes;
            if (reply.length < 13 || p[5] || u16(p + 6) < 16 || !u16(p + 9)) session.error = @"Controller ACL buffers unavailable.";
            else session.mtu = u16(p + 6);
        }
        if (!session.error && !NWBTCancelled) {
            uint8_t parameters[13] = {0}; memcpy(parameters, address, 6);
            put16(parameters + 6, 0xcc18); // DM1/DH1; exclude EDR packet types.
            parameters[8] = 1; parameters[12] = 1;
            if ([session command:0x0405 parameters:[NSData dataWithBytes:parameters length:13]]) session.pending = YES;
            fputs("NWBT phase: bounded connection attempt submitted\n", stderr);
            double deadline = now() + 6.0;
            while (!session.connected && !session.error && !NWBTCancelled && now() < deadline) [session pump];
            if (!session.connected && !session.error && !NWBTCancelled) session.error = @"Target connection timed out after six seconds.";
        }
        // Credits may delay an individual send; the overall ping window remains
        // bounded even if the target stops returning credits or responses.
        double pingDeadline = now() + NWBT_MAX_PING_SECONDS;
        for (uint8_t identifier = 1; identifier <= count && session.connected && !session.error && !NWBTCancelled; ++identifier) {
            if (now() >= pingDeadline) { session.error = @"Ping window deadline reached."; break; }
            double creditDeadline = MIN(now() + 1.0, pingDeadline);
            while ((!session.credits || session.auxiliary.count) && now() < creditDeadline && !session.error && !NWBTCancelled) [session pump];
            if (session.error || NWBTCancelled || !session.connected) break;
            if (!session.credits) { session.error = @"ACL transmission credit did not return."; break; }
            uint8_t nonce[8]; arc4random_buf(nonce, sizeof(nonce));
            session.nonce = [NSData dataWithBytes:nonce length:sizeof(nonce)]; session.echoID = identifier;
            session.echoReceived = NO; session.echoRejected = NO; session.sentAt = now();
            if (![session.acl send:[session signaling:8 identifier:identifier payload:session.nonce]]) { session.error = session.acl.error; break; }
            session.credits = 0; session.submitted++;
            double deadline = MIN(session.sentAt + 1.0, pingDeadline);
            while (now() < deadline && session.connected && !session.error && !NWBTCancelled) [session pump];
            NSMutableDictionary *sample = [@{@"sequence": @(identifier), @"reply": @(session.echoReceived), @"rejected": @(session.echoRejected)} mutableCopy];
            if (session.echoReceived) sample[@"rtt_ms"] = @(session.rtt);
            [session.samples addObject:sample];
            // Keep a one-second response deadline independent of spacing.
            // Pump during the gap so cancellation and remote link events work.
            double nextSend = MIN(session.sentAt + intervalSeconds, pingDeadline);
            if (identifier < count)
                while (now() < nextSend && session.connected && !session.error && !NWBTCancelled) [session pump];
        }
        NSString *originalError = session.error;
        [session cleanup];
        report[@"samples"] = session.samples; report[@"echo_requests_submitted"] = @(session.submitted);
        report[@"auxiliary_packets_submitted"] = @(session.auxiliarySent); report[@"local_hci_commands_submitted"] = @(session.commands);
        report[@"event_codes"] = session.eventCodes;
        report[@"disconnect_confirmed"] = @(session.disconnectConfirmed); report[@"connection_cancel_confirmed"] = @(session.cancelConfirmed);
        NSUInteger replies = 0; for (NSDictionary *sample in session.samples) if ([sample[@"reply"] boolValue]) replies++;
        report[@"echo_replies_verified"] = @(replies); report[@"l2ping_verified"] = @(replies > 0);
        if (NWBTCancelled) report[@"error"] = @"Diagnostic cancelled.";
        else if (originalError) report[@"error"] = originalError;
        else if (!replies) report[@"error"] = @"No matching L2CAP Echo Response received.";
        if (session.connected || (session.pending && !session.cancelConfirmed)) report[@"cleanup_warning"] = @"Link cleanup was not acknowledged before its deadline; restore the Bluetooth service.";
        return report;
    } @finally { NWBTCloseNativeChannel(acl); NWBTCloseNativeChannel(hci); }
}
