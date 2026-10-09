#import <UIKit/UIKit.h>
UIViewController *NWHotspotController(void);
void NWHotspotScannerStarted(id scanner, id adapter);
void NWHotspotStartReturned(id scanner);
void NWHotspotFound(id adapter, id device);
void NWHotspotFinished(id adapter, BOOL success);
void NWHotspotProgress(id adapter);
BOOL NWHotspotBusy(void);
#ifdef NW_UI_TESTING
int NWHotspotUIRegressionCheck(void);
int NWHotspotUIRegressionPresent(int phase);
#endif
