#import <UIKit/UIKit.h>
UIViewController *NWBLEMapController(void);
#ifdef NW_UI_TESTING
int NWBLEMapUIRegressionCheck(void);
int NWBLEMapVisibleUIRegressionCheck(UIViewController *view);
#endif
