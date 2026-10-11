#import "../src/bluetooth/NWBTUART.h"
#include <stdatomic.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
atomic_int NWBTCancelled = 0;
static NWBTUART *pair(int descriptors[2]) {
    assert(!socketpair(AF_UNIX,SOCK_STREAM,0,descriptors));
    return [[NWBTUART alloc] initWithTestDescriptor:descriptors[0]];
}
int main(void) { @autoreleasepool {
    // Kernel-control streams are not tty reads. A driver may normalize unused
    // line-editing characters without changing framing, speed or H4 octets.
    struct termios original = {0}, wanted = {0}, observed = {0};
    memset(original.c_cc, 7, sizeof(original.c_cc));
    wanted = original;
    NWBTUARTTestConfiguration(&wanted, &observed);
    assert(!memcmp(wanted.c_cc, original.c_cc, sizeof(original.c_cc)));
    observed = wanted;
    assert([NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    observed.c_cc[VMIN] = 0; observed.c_cc[VTIME] = 9;
    observed.c_cc[VEOF] = 4;
    observed.c_iflag ^= IGNPAR; // parity is disabled (8N1)
    observed.c_oflag ^= ONLCR; // ignored when OPOST is off
    observed.c_lflag ^= ECHOE; // ignored when echo and canonical mode are off
    cfsetispeed(&observed, 0); // Darwin/POSIX: input follows output speed
    NSDictionary *comparison = NWBTUARTTestConfiguration(&original, &observed);
    assert([comparison[@"matches"] boolValue] && [comparison[@"reported_differences"] count] >= 4);
    // Do not admit a different baud rate, framing, hardware flow control,
    // byte translation, software flow control, echo or canonical processing.
    const tcflag_t hardware[] = {CSIZE, CREAD, CLOCAL, CRTSCTS, PARENB, CSTOPB, HUPCL};
    for (NSUInteger i=0; i<sizeof(hardware)/sizeof(hardware[0]); ++i) {
        observed = wanted; observed.c_cflag ^= hardware[i];
        assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    }
    const tcflag_t inputs[] = {IGNBRK, BRKINT, PARMRK, ISTRIP, INLCR, IGNCR, ICRNL, IXON, IXOFF, IXANY};
    for (NSUInteger i=0; i<sizeof(inputs)/sizeof(inputs[0]); ++i) {
        observed = wanted; observed.c_iflag ^= inputs[i];
        assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    }
    const tcflag_t locals[] = {ICANON, ISIG, IEXTEN, ECHO, ECHONL, FLUSHO};
    for (NSUInteger i=0; i<sizeof(locals)/sizeof(locals[0]); ++i) {
        observed = wanted; observed.c_lflag ^= locals[i];
        assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    }
    observed = wanted; observed.c_oflag |= OPOST;
    assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    observed = wanted; cfsetispeed(&observed, 115200);
    assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    observed = wanted; cfsetospeed(&observed, 115200);
    assert(![NWBTUARTTestConfiguration(&original, &observed)[@"matches"] boolValue]);
    int fds[2]; NWBTUART *uart = pair(fds);
    const uint8_t command[] = {1,16,0}, expected[] = {1,1,16,0};
    assert([uart send:[NSData dataWithBytes:command length:sizeof(command)]]);
    uint8_t frame[4]; assert(read(fds[1],frame,sizeof(frame))==4 && !memcmp(frame,expected,4));
    const uint8_t event[] = {4,14,4,1,1,16,0};
    assert(write(fds[1],event,2)==2 && ![uart read]);
    assert(write(fds[1],event+2,5)==5);
    NSData *received = [uart read];
    assert(received.length==6 && !memcmp(received.bytes,event+1,6));
    assert([uart.diagnostics[@"rx_events"] intValue]==1);
    // Stop must not prevent cleanup writes. Outer HCI consumer owns cancellation.
    atomic_store(&NWBTCancelled,1);
    const uint8_t cleanup[] = {0x39,0x20,6,0,1,0,0,0,0};
    assert([uart send:[NSData dataWithBytes:cleanup length:sizeof(cleanup)]]);
    atomic_store(&NWBTCancelled,0);
    [uart close]; [uart close]; assert(uart.descriptor==-1 && fcntl(fds[0],F_GETFD)==-1); close(fds[1]);
    uart=pair(fds);
    const uint8_t forbidden[] = {3,12,0}; // HCI Reset never allowed
    assert(![uart send:[NSData dataWithBytes:forbidden length:3]] && uart.error);
    [uart close]; close(fds[1]);
    NSMutableDictionary *cancelled = [@{@"error": @"Diagnostic cancelled."} mutableCopy];
    NWBTRecordTransportClosure(cancelled, @{@"cleanup_error": @"UART restore rejected."});
    assert([cancelled[@"cleanup_warning"] isEqual:@"UART restore rejected."]);
    assert([cancelled[@"error"] isEqual:@"Diagnostic cancelled."]);
    NSMutableDictionary *successful = [NSMutableDictionary new];
    NWBTRecordTransportClosure(successful, @{@"configuration_restored": @YES});
    assert(!successful[@"cleanup_warning"] && !successful[@"error"]);
    uart=pair(fds); close(fds[1]);
    assert(![uart read] && uart.error); [uart close];
    uart=pair(fds);
    uint8_t invalid=7; assert(write(fds[1],&invalid,1)==1);
    assert(![uart read] && uart.error); [uart close]; close(fds[1]);
    uart=pair(fds); close(fds[1]);
    assert(![uart send:[NSData dataWithBytes:command length:3]] && uart.error); [uart close];
    // Saturate the transmit socket and prove that backpressure cannot hang the
    // privileged worker. Nothing consumes data on the peer during this test.
    uart=pair(fds);
    int small=1024; assert(!setsockopt(fds[0],SOL_SOCKET,SO_SNDBUF,&small,sizeof(small)));
    uint8_t padding[512]={0};
    while (send(fds[0],padding,sizeof(padding),0)>0) {}
    assert(errno==EAGAIN || errno==EWOULDBLOCK);
    double started=NSProcessInfo.processInfo.systemUptime;
    assert(![uart send:[NSData dataWithBytes:command length:3]] && uart.error);
    assert(NSProcessInfo.processInfo.systemUptime-started < 2.0);
    [uart close]; close(fds[1]);
    puts("UART effective configuration, hardware rejection, socketpair, cancellation, EOF and ownership passed");
    return 0;
} }
