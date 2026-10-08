#import <UIKit/UIKit.h>

void NWPresentDeviceBrowser(UIViewController *presenter);
void NWRefreshVisibleDeviceBrowser(void);
#ifdef NW_UI_TESTING
int NWDeviceBrowserUIRegressionCheck(void);
int NWDeviceBrowserUIRegressionPresent(void);
int NWDeviceBrowserUIRegressionSearch(void);
int NWDeviceBrowserUIRegressionSelect(void);
int NWDeviceBrowserUIRegressionMenu(void);
#endif
