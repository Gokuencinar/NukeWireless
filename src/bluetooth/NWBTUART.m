#import "NWBTUART.h"
#import "NWBTBridge.h"
#import "NWBTNative.h"
#include "NWBTH4.h"
#include "NWBTHCIRead.h"
#include "NWBTLab.h"
#include <sys/socket.h>
#include <sys/kern_control.h>
#include <sys/sys_domain.h>
#include <sys/sysctl.h>
#include <sys/ioctl.h>
#include <sys/ttycom.h>
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
    report[@"transport_details"] = uart.diagnostics;
    *error = report;
}
@implementation NWBTUART
- (instancetype)init {
    if ((self = [super init])) {
        _descriptor = -1;
        _details = [@{@"transport": @"uart-h4", @"experimental": @YES,
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
    if (getsockopt(fd, SYSPROTO_CONTROL, TIOCGETA, &uart->_original, &size) < 0 || size != sizeof(uart->_original)) {
        *error = uartError(@"uart_configuration_read", @"UART termios contract could not be read.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    struct termios configured = uart->_original;
    cfmakeraw(&configured);
    configured.c_iflag |= IGNPAR;
    configured.c_cflag = CS8 | CREAD | CLOCAL | CRTSCTS;
    if (cfsetspeed(&configured, 3000000) < 0) {
        *error = uartError(@"uart_configuration_speed", @"UART link speed could not be configured.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    // A rejected setsockopt might have changed fields: always attempt restoration.
    uart->_configured = YES;
    if (setsockopt(fd, SYSPROTO_CONTROL, TIOCSETA, &configured, sizeof(configured)) < 0) {
        *error = uartError(@"uart_configuration_write", @"UART termios configuration was rejected.", errno);
        closeWithEvidence(uart, error); return nil;
    }
    struct termios observed = {0}; size = sizeof(observed);
    if (getsockopt(fd, SYSPROTO_CONTROL, TIOCGETA, &observed, &size) < 0 ||
        size != sizeof(observed) || !sameConfiguration(&configured, &observed)) {
        *error = uartError(@"uart_configuration_verify", @"UART configuration readback differs from the requested contract.", errno);
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
        BOOL restored = setsockopt(_descriptor, SYSPROTO_CONTROL, TIOCSETA, &_original, sizeof(_original)) == 0 &&
            getsockopt(_descriptor, SYSPROTO_CONTROL, TIOCGETA, &observed, &size) == 0 &&
            size == sizeof(observed) && sameConfiguration(&_original, &observed);
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
