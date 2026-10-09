#import <UIKit/UIKit.h>
UIViewController *NWBluetoothController(void);
BOOL NWBluetoothBusy(void);
FOUNDATION_EXPORT NSString *const NWBluetoothChanged;
BOOL NWBluetoothStopping(void);
void NWBluetoothStop(void);
NSString *NWBluetoothEmissionIssue(void);
void NWBluetoothReadDiagnostics(void (^completion)(NSDictionary *report));
BOOL NWBluetoothStartCapabilityDiagnostic(void);
#ifdef NW_UI_TESTING
int NWBluetoothUIRegressionCatalogState(int state);
#endif
