#import <Foundation/Foundation.h>
NSString *NWText(NSString *key);
NSBundle *NWResourceBundle(void);
NSString *NWVendorForMAC(NSString *mac);
BOOL NWVendorUpdateBusy(void);
void NWUpdateVendors(void (^completion)(NSError *error));
BOOL NWRestoreVendors(NSError **error);
double NWCurrentPacketInterval(void);
void NWSetPacketInterval(double value);
void NWInstallPacketIntervalHook(void);

NSDictionary *NWParseVendorText(NSString *text);
NSArray *NWPacketArguments(NSArray *arguments, NSString *path, double interval);
