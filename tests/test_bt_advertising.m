// Exercise the real advertising/session code with a deterministic HCI peer.
// This tests scheduling and cleanup, never physical UART or radio reception.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <unistd.h>
#include <poll.h>
#import "../src/bluetooth/NWBTNative.h"
static double clockValue;
static BOOL cancelOnSleep;
double NWBTLabTestTime(void) { return clockValue; }
static int testSleep(useconds_t microseconds) {
    clockValue += microseconds / 1000000.0;
    if (cancelOnSleep) atomic_store(&NWBTCancelled, 1);
    return 0;
}
static int testPoll(struct pollfd *fds, nfds_t count, int timeout) {
    (void)fds; (void)count; clockValue += timeout / 1000.0; return 0;
}
#define usleep testSleep
#define poll testPoll
#include "../src/bluetooth/NWBTL2Ping.m"
#undef usleep
#undef poll

NSDictionary *NWBTNativeGuard(void) { return nil; }
NSDictionary *NWBTLegacyGuard(void) { return nil; }
NSString *NWBTNativeTransport(void) { return @"skywalk"; }
void *NWBTOpenExclusiveNativeChannel(NSString *protocol, uint64_t *capacity, NSDictionary **error) {
    (void)protocol; (void)capacity; (void)error; return NULL;
}
void NWBTCloseNativeChannel(void *channel) { (void)channel; }

@interface TestRing : NWBTRing
@property(nonatomic, strong) NSMutableArray<NSData *> *writes;
@property(nonatomic, strong) NSData *reply;
@property(nonatomic, strong) NSMutableArray<NSData *> *addresses;
@property(nonatomic, strong) NSMutableArray<NSData *> *payloads;
@property(nonatomic) BOOL capacityQuery, missingSetter, closed, failCleanup;
@property(nonatomic) unsigned setLimit, failOpcode, dropOpcode, enables;
@end
@implementation TestRing
- (BOOL)send:(NSData *)packet {
    [self.writes addObject:packet];
    const uint8_t *p = packet.bytes; uint16_t opcode = u16(p);
    size_t size = NWBTReadReplySize(opcode) ?: NWBTLabReplySize(opcode);
    assert(packet.length == (NSUInteger)p[2] + 3 && size);
    if (opcode == 0x203b) assert(self.capacityQuery); // Never probe absent commands.
    uint8_t bytes[70] = {0x0e, (uint8_t)(size + 3), 1, p[0], p[1], 0};
    if (opcode == 0x1001) bytes[6] = 9;
    if (opcode == 0x1002) {
        // Exact bitmap supplied by the iPhone10,2 / 20H240 tester.
        const char *hex = "ffffff03ccffeffffffffc1ff20fe8fe3ff78fff1c00040061f7ffff7ff8ffffffffffff7fffff09000000000000000000000000000000000000000000000000";
        for (unsigned i = 0; i < 64; ++i) { unsigned value; assert(sscanf(hex + i*2, "%2x", &value) == 1); bytes[6+i] = value; }
        if (self.capacityQuery) bytes[42] |= 0x80;
        if (self.missingSetter) bytes[42] &= ~0x04;
    }
    if (opcode == 0x203b) bytes[6] = self.setLimit;
    if (opcode == 0x2036) bytes[6] = 8;
    if (opcode == 0x2035) [self.addresses addObject:[packet subdataWithRange:NSMakeRange(3, 7)]];
    if (opcode == 0x2037) [self.payloads addObject:[packet subdataWithRange:NSMakeRange(3, packet.length-3)]];
    if (opcode == 0x2039 && p[3]) {
        self.enables++; unsigned ticks = u16(p+6); assert(ticks > 0 && ticks <= 1000);
    }
    if (opcode == self.failOpcode || (self.failCleanup && (opcode == 0x203c || (opcode == 0x2039 && !p[3])))) bytes[5] = 0x0c;
    self.reply = opcode == self.dropOpcode ? nil : [NSData dataWithBytes:bytes length:size+5];
    return YES;
}
- (NSData *)read { NSData *value = self.reply; self.reply = nil; return value; }
- (void)close { self.closed = YES; }
- (NSDictionary *)transportDiagnostics {
    return @{@"transport": @"uart-h4", @"channel_opened": @YES, @"channel_closed": @(self.closed),
        @"wake_opened": @YES, @"wake_closed": @(self.closed), @"configuration_restored": @YES,
        @"commands_written": @(self.writes.count)};
}
@end
static TestRing *peer;
id NWBTLabTestRing(void) { return peer; }
static void reset(void) {
    peer = [TestRing new]; peer.writes = [NSMutableArray new]; peer.addresses = [NSMutableArray new]; peer.payloads = [NSMutableArray new];
    peer.setLimit = 6; clockValue = 100; cancelOnSleep = NO; atomic_store(&NWBTCancelled, 0);
}
static unsigned countOpcode(uint16_t opcode) {
    unsigned count = 0; for (NSData *packet in peer.writes) if (u16(packet.bytes) == opcode) count++; return count;
}
static void clean(NSDictionary *report) {
    assert(peer.closed && [report[@"advertising_stopped_acknowledged"] boolValue] && [report[@"advertising_set_removed"] boolValue]);
    assert(NWBTUARTCanPreserveService(report));
}
int main(void) { @autoreleasepool {
    NSArray *models = @[@0, @1, @2, @3, @4, @5];
    reset(); NSDictionary *report = NWBTAdvertiseCatalogLab(0, @[@0]);
    assert(!report[@"error"] && peer.enables == 1 && !countOpcode(0x203b)); clean(report);
    reset(); report = NWBTAdvertiseCatalogLab(0, models);
    assert(!report[@"error"] && peer.enables == 6 && !countOpcode(0x203b)); clean(report);
    assert([report[@"advertising_schedule"] isEqual:@"sequential_single_set"] && !report[@"supported_advertising_sets"]);
    assert([report[@"models_enabled_count"] unsignedIntValue] == 6 && clockValue <= 110.021);
    for (unsigned i = 0; i < 6; ++i) {
        const uint8_t *address = peer.addresses[i].bytes; const uint8_t *data = peer.payloads[i].bytes;
        assert(address[0] == NWBT_LAB_MULTI_HANDLE && address[1] == i+1 && data[0] == address[0]);
        assert(u16(data+11) == NWCatalogProfileID(0, i));
    }
    reset(); peer.capacityQuery = YES; report = NWBTAdvertiseCatalogLab(0, models);
    assert(!report[@"error"] && countOpcode(0x203b) == 1 && [report[@"advertising_schedule"] isEqual:@"simultaneous"]); clean(report);
    reset(); peer.capacityQuery = YES; peer.setLimit = 2; report = NWBTAdvertiseCatalogLab(0, models);
    assert(!report[@"error"] && peer.enables == 6 && [report[@"advertising_schedule"] isEqual:@"sequential_single_set"]); clean(report);
    reset(); peer.capacityQuery = YES; peer.setLimit = 0; report = NWBTAdvertiseCatalogLab(0, models);
    assert(report[@"error"] && !peer.enables && !countOpcode(0x2036) && peer.closed);
    reset(); cancelOnSleep = YES; report = NWBTAdvertiseCatalogLab(0, models);
    assert(report[@"error"] && peer.enables == 1 && !countOpcode(0x203b)); clean(report);
    assert([report[@"controller_advertising_acknowledged"] boolValue] && ![report[@"selection_completed"] boolValue]);
    reset(); peer.dropOpcode = 0x2039; report = NWBTAdvertiseCatalogLab(0, models);
    assert(report[@"error"] && peer.enables == 1 && countOpcode(0x203c) == 1 && peer.closed);
    assert(!NWBTUARTCanPreserveService(report));
    reset(); peer.failOpcode = 0x2037; report = NWBTAdvertiseCatalogLab(0, models);
    assert(report[@"error"] && !peer.enables && countOpcode(0x203c) == 1 && peer.closed);
    reset(); peer.failCleanup = YES; report = NWBTAdvertiseCatalogLab(0, models);
    assert(report[@"error"] && peer.closed && !NWBTUARTCanPreserveService(report));
    reset(); peer.missingSetter = YES; report = NWBTAdvertiseCatalogLab(0, models);
    assert([report[@"error_code"] isEqual:@"unsupported"] && !countOpcode(0x2036) && peer.closed);
    reset(); report = NWBTAdvertiseApplePairingLab(); assert(!report[@"error"] && !countOpcode(0x203b)); clean(report);
    // Repeated operations never retain handles or cancellation from the last run.
    reset(); report = NWBTAdvertiseCatalogLab(1, @[@0]); assert(!report[@"error"]); clean(report);
    puts("PASS: tester bitmap, single/sequential/simultaneous advertising, deadlines, Stop, rejection, lost ACK and cleanup");
} }
