#import "../src/bluetooth/NWBTUART.h"
#include <stdatomic.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <assert.h>
#include <string.h>
#include <stdio.h>
atomic_int NWBTCancelled = 0;
static NWBTUART *pair(int descriptors[2]) {
    assert(!socketpair(AF_UNIX,SOCK_STREAM,0,descriptors));
    return [[NWBTUART alloc] initWithTestDescriptor:descriptors[0]];
}
int main(void) { @autoreleasepool {
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
    uart=pair(fds); close(fds[1]);
    assert(![uart read] && uart.error); [uart close];
    uart=pair(fds);
    uint8_t invalid=7; assert(write(fds[1],&invalid,1)==1);
    assert(![uart read] && uart.error); [uart close]; close(fds[1]);
    uart=pair(fds); close(fds[1]);
    assert(![uart send:[NSData dataWithBytes:command length:3]] && uart.error); [uart close];
    puts("UART socketpair framing, cancellation cleanup, allowlist, EOF and ownership passed");
    return 0;
} }
