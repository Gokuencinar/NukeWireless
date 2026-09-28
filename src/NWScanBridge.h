#import <UIKit/UIKit.h>
FOUNDATION_EXPORT NSNotificationName const NWStateChanged;
void NWInstallScanHooks(void);
void NWReconcileDeviceStates(void);
BOOL NWScanBusy(void);
BOOL NWBulkBusy(void);
NSString *NWScanSummary(void);
NSString *NWBulkTitle(void);
BOOL NWRefreshScan(void);
void NWConfirmBulk(UIViewController *presenter);
void NWLogBulkStatus(void);
