#import <UIKit/UIKit.h>
FOUNDATION_EXPORT NSNotificationName const NWStateChanged;
void NWInstallScanHooks(void);
void NWReconcileDeviceStates(void);
BOOL NWScanBusy(void);
BOOL NWBulkBusy(void);
NSString *NWScanSummary(void);
NSString *NWBulkTitle(void);
BOOL NWRefreshScan(void);
void NWMaintainWiFiScan(void);
void NWConfirmBulk(UIViewController *presenter);
BOOL NWCanRestartForLanguage(void);
#ifdef NW_UI_TESTING
void NWBeginWiFiScanUITest(void);
void NWEndWiFiScanUITest(void);
#endif
// Presentation-only copies. Never expose native mutable devices to the browser.
NSArray<NSDictionary<NSString *, id> *> *NWDeviceSnapshot(void);
uint64_t NWDeviceGeneration(void);
// Read-only existing gateway reader; call off the UI thread.
NSString *NWReadGatewayAddress(void);
