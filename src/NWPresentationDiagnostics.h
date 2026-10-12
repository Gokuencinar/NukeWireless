#import <UIKit/UIKit.h>
void NWPresentationDiagnosticsInstall(void (^reconcile)(UIViewController *root));
#ifdef NW_UI_TESTING
int NWPresentationDiagnosticsUIRegressionCheck(void);
#endif
