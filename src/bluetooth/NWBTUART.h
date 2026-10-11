#import <Foundation/Foundation.h>

// Probe only queries the kernel-control ID. It never connects, configures the
// UART, retires bluetoothd, or submits HCI. Admission is firmware-specific.
NSDictionary *NWBTUARTProbe(void);
void NWBTRecordTransportClosure(NSMutableDictionary *report, NSDictionary *details);
#ifdef NW_BT_UART_TESTING
#include <termios.h>
NSDictionary *NWBTUARTTestConfiguration(struct termios *value, const struct termios *observed);
#endif
@interface NWBTUART : NSObject
@property(nonatomic, readonly) int descriptor;
@property(nonatomic, readonly, copy) NSString *error;
@property(nonatomic, readonly) NSDictionary *diagnostics;
+ (instancetype)openExclusive:(NSDictionary **)error;
- (BOOL)send:(NSData *)command;
- (NSData *)read;
- (void)close;
#ifdef NW_BT_UART_TESTING
// Ownership is transferred; socketpair tests bypass kernel control / termios.
- (instancetype)initWithTestDescriptor:(int)descriptor;
#endif
@end
