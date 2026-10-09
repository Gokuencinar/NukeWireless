#import <UIKit/UIKit.h>
UIViewController *NWDiagnosticsController(void);
void NWDiagnosticsInstall(void);
#ifdef NW_UI_TESTING
int NWDiagnosticsUIRegressionCheck(void);
#endif
