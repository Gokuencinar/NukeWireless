#import "NWBTUART.h"
#import "NWBTBridge.h"
#import "NWBTNative.h"
#include "NWBTH4.h"
#include "NWBTHCIRead.h"
#include "NWBTLab.h"
#include "NWBTUARTABI.h"
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

// Public Darwin declarations, not numeric copies of a historical proxy ABI.
_Static_assert(sizeof(struct sockaddr_ctl) == 32, "Darwin kernel control address");
_Static_assert(sizeof(struct termios) == 72, "64-bit Darwin termios");
static double uartTime(void) { return NSProcessInfo.processInfo.systemUptime; }
void NWBTRecordTransportClosure(NSMutableDictionary *report, NSDictionary *details) {
    report[@"transport_details"] = details;
    if (details[@"cleanup_error"]) {
        report[@"cleanup_warning"] = details[@"cleanup_error"];
        report[@"error"] = report[@"error"] ?: details[@"cleanup_error"];
    }
}
static NSDictionary *uartError(NSString *stage, NSString *message, int number) {
    return @{@"version": NWBT_VERSION, @"stage": stage, @"error": message,
        @"errno": @(number), @"transport": @"uart-h4", @"experimental": @YES};
}
static NSString *systemValue(const char *name) {
    char value[128] = {0}; size_t size = sizeof(value);
    return !sysctlbyname(name, value, &size, NULL, 0) && size > 0 && size <= sizeof(value) &&
        value[size - 1] == 0 ? [NSString stringWithUTF8String:value] : @"unknown";
}
static int controlSocket(struct ctl_info *info, NSDictionary **error) {
    int fd = socket(AF_SYSTEM, SOCK_STREAM, SYSPROTO_CONTROL);
    if (fd < 0) { *error = uartError(@"uart_socket", @"Cannot create UART control socket.", errno); return -1; }
    memset(info, 0, sizeof(*info));
    strlcpy(info->ctl_name, "com.apple.uart.bluetooth", sizeof(info->ctl_name));
    if (ioctl(fd, CTLIOCGINFO, info) < 0 || !info->ctl_id) {
        int number = errno; close(fd);
        *error = uartError(@"uart_registry", @"UART Bluetooth control is not registered or cannot be queried.", number);
        return -1;
    }
    return fd;
}
NSDictionary *NWBTUARTProbe(void) {
    NSString *machine = systemValue("hw.machine"), *build = systemValue("kern.osversion");
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (![machine isEqual:@"iPhone10,2"] || ![build isEqual:@"20H240"] ||
        os.majorVersion != 16 || os.minorVersion != 7 || os.patchVersion != 4)
        return uartError(@"uart_admission", @"Experimental UART contract requires iPhone10,2 / iOS 16.7.4 (20H240).", 0);
    struct ctl_info info; NSDictionary *error = nil;
    int fd = controlSocket(&info, &error);
    if (fd < 0) return error;
    close(fd);
    return @{@"stage": @"uart_registered", @"transport": @"uart-h4", @"experimental": @YES,
        @"control_id": @(info.ctl_id), @"machine": machine, @"os_build": build,
        @"channel_opened": @NO, @"hci_commands_submitted": @0};
}
static void appendEvent(const uint8_t *bytes, size_t length, void *context) {
    NSMutableData *data = (__bridge NSMutableData *)context;
    [data appendBytes:bytes length:length];
}
static BOOL sameConfiguration(const struct termios *a, const struct termios *b) {
    return a->c_iflag == b->c_iflag && a->c_oflag == b->c_oflag &&
        a->c_cflag == b->c_cflag && a->c_lflag == b->c_lflag &&
        cfgetispeed(a) == cfgetispeed(b) && cfgetospeed(a) == cfgetospeed(b) &&
        !memcmp(a->c_cc, b->c_cc, sizeof(a->c_cc));
}
static NSDictionary *configurationSnapshot(const struct termios *value) {
    NSMutableArray *characters = [NSMutableArray new];
    for (NSUInteger i = 0; i < NCCS; ++i) [characters addObject:@(value->c_cc[i])];
    return @{@"input_flags": @(value->c_iflag), @"output_flags": @(value->c_oflag),
        @"control_flags": @(value->c_cflag), @"local_flags": @(value->c_lflag),
        @"input_speed": @(cfgetispeed(value)), @"output_speed": @(cfgetospeed(value)),
        @"control_characters": characters};
}
static void configureStream(struct termios *value) {
    // Preserve the request accepted by iPhone10,2 / 20H240 and the historical
    // UART client. Keep c_cc intact: socket reads do not use tty VMIN/VTIME.
    value->c_iflag = IGNBRK | IGNPAR; value->c_oflag = 0; value->c_lflag = 0;
    value->c_cflag = CS8 | CREAD | CLOCAL | CRTSCTS;
}
static NSDictionary *configurationComparison(const struct termios *wanted, const struct termios *observed) {
    NSMutableArray *mismatches = [NSMutableArray new], *normalizations = [NSMutableArray new];
    // Observed in the exact admitted firmware's diagnostic4 readback. Accept
    // this complete representation only, not arbitrary missing control bits.
    // The request is unchanged; no inference that CREAD can safely be omitted.
    BOOL kernelStreamRepresentation = wanted->c_cflag == (CS8 | CREAD | CLOCAL | CRTSCTS) &&
        observed->c_cflag == (CS8 | CRTSCTS) && wanted->c_iflag == (IGNBRK | IGNPAR) &&
        observed->c_iflag == 0;
    tcflag_t expectedInput = kernelStreamRepresentation ? 0 : wanted->c_iflag;
    tcflag_t expectedControl = kernelStreamRepresentation ? (CS8 | CRTSCTS) : wanted->c_cflag;
    if (kernelStreamRepresentation) [normalizations addObject:@"20H240_kernel_control_tty_flags"];
    // Compare effective byte processing, not inactive tty bookkeeping. With
    // 8N1, parity-error handling flags cannot change ordinary H4 octets.
    tcflag_t inputMask = IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON | IXOFF | IXANY;
    if ((wanted->c_cflag | observed->c_cflag) & PARENB) inputMask |= INPCK | IGNPAR;
    tcflag_t localMask = ICANON | ISIG | IEXTEN | ECHO | ECHONL | FLUSHO;
    if ((expectedInput & inputMask) != (observed->c_iflag & inputMask)) [mismatches addObject:@"input_flags"];
    if ((wanted->c_oflag & OPOST) != (observed->c_oflag & OPOST)) [mismatches addObject:@"output_processing"];
    // Framing and both RTS/CTS directions still have to match exactly.
    if (expectedControl != observed->c_cflag) [mismatches addObject:@"control_flags"];
    if ((wanted->c_lflag & localMask) != (observed->c_lflag & localMask)) [mismatches addObject:@"local_processing"];
    speed_t inputSpeed = cfgetispeed(observed) ?: cfgetospeed(observed);
    if (cfgetispeed(wanted) != inputSpeed) [mismatches addObject:@"input_speed"];
    if (cfgetospeed(wanted) != cfgetospeed(observed)) [mismatches addObject:@"output_speed"];
    if (wanted->c_iflag != observed->c_iflag) [normalizations addObject:@"input_flags"];
    if (wanted->c_cflag != observed->c_cflag) [normalizations addObject:@"control_flags"];
    if (wanted->c_oflag != observed->c_oflag) [normalizations addObject:@"output_flags"];
    if (wanted->c_lflag != observed->c_lflag) [normalizations addObject:@"local_flags"];
    if (memcmp(wanted->c_cc, observed->c_cc, sizeof(wanted->c_cc))) [normalizations addObject:@"tty_control_characters"];
    if (!cfgetispeed(observed)) [normalizations addObject:@"input_speed_follows_output"];
    return @{@"policy": @"h4-stream-effective-v2", @"matches": @(mismatches.count == 0),
        @"mismatches": mismatches, @"reported_differences": normalizations};
}
@interface NWBTUART () {
    int _descriptor;
    struct termios _original;
    BOOL _configured;
    NWBTH4Parser _parser;
    NSMutableDictionary *_details;
}
@property(nonatomic, readwrite, copy) NSString *error;
@end
static void closeWithEvidence(NWBTUART *uart, NSDictionary **error) {
    [uart close];
    NSMutableDictionary *report = [*error mutableCopy];
    NWBTRecordTransportClosure(report, uart.diagnostics);
    *error = report;
}
@implementation NWBTUART
- (instancetype)init {
    if ((self = [super init])) {
        _descriptor = -1;
        _details = [@{@"transport": @"uart-h4", @"experimental": @YES,
            @"configuration_contract": @"iphone10_2-20H240-uart-stream-v1", @"commands_written": @0,
            @"channel_opened": @NO, @"configuration_verified": @NO} mutableCopy];
    }
    return self;
}
+ (instancetype)openExclusive:(NSDictionary **)error {
    if (getuid() != 0) { *error = uartError(@"permissions", @"Exclusive UART requires the privileged worker.", 0); return nil; }
    NSDictionary *probe = NWBTUARTProbe();
    if (probe[@"error"]) { *error = probe; return nil; }
    NWBTUART *uart = [NWBTUART new];
    struct ctl_info info;
    uart->_descriptor = controlSocket(&info, error);
    if (uart->_descriptor < 0) return nil;
    int fd = uart->_descriptor;
    int flags = fcntl(fd, F_GETFL);
    int noSignal = 1;
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal)) < 0) {
        *error = uartError(@"uart_socket", @"Cannot set bounded UART socket flags.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    struct sockaddr_ctl address = {0};
    address.sc_len = sizeof(address); address.sc_family = AF_SYSTEM;
    address.ss_sysaddr = AF_SYS_CONTROL; address.sc_id = info.ctl_id;
    int result = connect(fd, (struct sockaddr *)&address, sizeof(address));
    if (result < 0 && errno == EINPROGRESS) {
        double deadline = uartTime() + 0.5;
        do {
            struct pollfd p = {fd, POLLOUT, 0};
            result = poll(&p, 1, 20);
            if (result > 0) {
                int number = 0; socklen_t size = sizeof(number);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &number, &size) < 0) result = -1;
                else { errno = number; result = number ? -1 : 0; }
                break;
            }
            if (result < 0 && errno != EINTR) break;
            result = -1; errno = ETIMEDOUT;
        } while (uartTime() < deadline && !NWBTCancelled);
    }
    if (result < 0) {
        *error = uartError(@"uart_connect", @"Exclusive UART connection failed.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    uart->_details[@"channel_opened"] = @YES;
    socklen_t size = sizeof(uart->_original);
    int readResult = getsockopt(fd, SYSPROTO_CONTROL, TIOCGETA, &uart->_original, &size);
    int readError = readResult < 0 ? errno : 0;
    uart->_details[@"original_read"] = @{@"result": @(readResult), @"errno": @(readError), @"size": @(size)};
    if (readResult < 0 || size != sizeof(uart->_original)) {
        *error = uartError(@"uart_configuration_read", @"UART termios contract could not be read.", readError);
        closeWithEvidence(uart, error); return nil;
    }
    uart->_details[@"original_configuration"] = configurationSnapshot(&uart->_original);
    struct termios configured = uart->_original;
    configureStream(&configured);
    if (cfsetspeed(&configured, 3000000) < 0) {
        *error = uartError(@"uart_configuration_speed", @"UART link speed could not be configured.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    uart->_details[@"requested_configuration"] = configurationSnapshot(&configured);
    // A rejected setsockopt might have changed fields: always attempt restoration.
    uart->_configured = YES;
    if (setsockopt(fd, SYSPROTO_CONTROL, TIOCSETA, &configured, sizeof(configured)) < 0) {
        *error = uartError(@"uart_configuration_write", @"UART termios configuration was rejected.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    struct termios observed = {0}; size = sizeof(observed);
    readResult = getsockopt(fd, SYSPROTO_CONTROL, TIOCGETA, &observed, &size);
    readError = readResult < 0 ? errno : 0;
    uart->_details[@"configuration_readback"] = @{@"result": @(readResult), @"errno": @(readError), @"size": @(size)};
    if (readResult < 0 || size != sizeof(observed)) {
        *error = uartError(@"uart_configuration_readback", @"UART configuration readback failed or returned an invalid length.", readError);
        closeWithEvidence(uart, error); return nil;
    }
    uart->_details[@"observed_configuration"] = configurationSnapshot(&observed);
    NSDictionary *comparison = configurationComparison(&configured, &observed);
    uart->_details[@"configuration_comparison"] = comparison;
    if (![comparison[@"matches"] boolValue]) {
        *error = uartError(@"uart_configuration_verify", @"UART effective configuration differs from the requested contract.", 0);
        closeWithEvidence(uart, error); return nil;
    }
    uart->_details[@"configuration_verified"] = @YES;
    uart->_details[@"link_speed"] = @3000000;
    return uart;
}
- (int)descriptor { return _descriptor; }
- (NSDictionary *)diagnostics {
    NSMutableDictionary *result = [_details mutableCopy];
    result[@"rx_bytes"] = @(_parser.bytes); result[@"rx_events"] = @(_parser.events);
    result[@"ignored_data_packets"] = @(_parser.ignored);
    result[@"partial_rx_bytes"] = @(_parser.used);
    if (self.error) result[@"io_error"] = self.error;
    return result;
}
- (BOOL)send:(NSData *)command {
    if (self.error) return NO;
    const uint8_t *p = command.bytes;
    if (_descriptor < 0 || command.length < 3 || command.length > 258 || command.length != (size_t)p[2] + 3 ||
        (!NWBTReadReplySize(p[0] | (uint16_t)p[1] << 8) && !NWBTLabReplySize(p[0] | (uint16_t)p[1] << 8))) {
        self.error = @"UART command outside bounded HCI allowlist."; return NO;
    }
    uint8_t frame[259] = {1}; memcpy(frame + 1, p, command.length);
    size_t sent = 0, length = command.length + 1;
    double deadline = uartTime() + 0.5;
    // Finish any partial frame even on cancellation; the caller owns cancellation
    // between commands and must also be able to submit its cleanup commands.
    while (sent < length && uartTime() < deadline) {
        ssize_t count = send(_descriptor, frame + sent, length - sent, 0);
        if (count > 0) { sent += (size_t)count; continue; }
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd pfd = {_descriptor, POLLOUT, 0};
            int ready = poll(&pfd, 1, 20);
            if ((ready >= 0 || errno == EINTR) && !(pfd.revents & (POLLERR | POLLHUP | POLLNVAL))) continue;
        }
        self.error = @"UART H4 command write failed."; return NO;
    }
    if (sent != length) { self.error = @"UART H4 command write deadline expired."; return NO; }
    _details[@"commands_written"] = @([_details[@"commands_written"] unsignedIntegerValue] + 1);
    return YES;
}
- (NSData *)read {
    if (self.error || _descriptor < 0) return nil;
    uint8_t bytes[512];
    ssize_t length = recv(_descriptor, bytes, sizeof(bytes), 0);
    if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return nil;
    if (length <= 0) { self.error = @"UART H4 stream closed or receive failed."; return nil; }
    NSMutableData *events = [NSMutableData new];
    if (!NWBTH4Feed(&_parser, bytes, (size_t)length, appendEvent, (__bridge void *)events)) {
        self.error = @"UART H4 framing or receive bound failed."; return nil;
    }
    return events.length ? events : nil;
}
- (void)close {
    if (_descriptor < 0) return;
    if (_configured) {
        struct termios observed = {0}; socklen_t size = sizeof(observed);
        int writeResult = setsockopt(_descriptor, SYSPROTO_CONTROL, TIOCSETA, &_original, sizeof(_original));
        int writeError = writeResult < 0 ? errno : 0;
        int readResult = writeResult < 0 ? -1 : getsockopt(_descriptor, SYSPROTO_CONTROL, TIOCGETA, &observed, &size);
        int readError = writeResult < 0 ? 0 : readResult < 0 ? errno : 0;
        _details[@"restoration_io"] = @{@"write_result": @(writeResult), @"write_errno": @(writeError),
            @"read_attempted": @(writeResult == 0), @"read_result": @(readResult), @"read_errno": @(readError), @"size": @(size)};
        BOOL validRead = writeResult == 0 && readResult == 0 && size == sizeof(observed);
        if (validRead) _details[@"restored_configuration"] = configurationSnapshot(&observed);
        // Restore the full original state; do not weaken recovery validation.
        BOOL restored = validRead && sameConfiguration(&_original, &observed);
        _details[@"configuration_restored"] = @(restored);
        if (!restored) _details[@"cleanup_error"] = @"Original UART configuration could not be verified after restoration.";
        _configured = NO;
    }
    close(_descriptor); _descriptor = -1; _details[@"channel_closed"] = @YES;
}
- (void)dealloc { [self close]; }
#ifdef NW_BT_UART_TESTING
- (instancetype)initWithTestDescriptor:(int)descriptor {
    if ((self = [self init])) {
        _descriptor = descriptor;
        fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK);
        int noSignal = 1;
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    }
    return self;
}
#endif
@end
#ifdef NW_BT_UART_TESTING
NSDictionary *NWBTUARTTestConfiguration(struct termios *value, const struct termios *observed) {
    configureStream(value); cfsetspeed(value, 3000000);
    return configurationComparison(value, observed);
}
#endif
