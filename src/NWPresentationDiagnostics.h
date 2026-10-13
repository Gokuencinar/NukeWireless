#import <UIKit/UIKit.h>
void NWPresentationDiagnosticsInstall(void (^reconcile)(UIViewController *root));
// A bounded, passive snapshot of the main interface before/after a late
// SwiftUI onboarding transition. Does not trigger reconciliation itself.
void NWPresentationDiagnosticsRecordOnboarding(NSString *phase, NSDictionary *beforeTabs);
#ifdef NW_UI_TESTING
int NWPresentationDiagnosticsUIRegressionCheck(void);
#endif
