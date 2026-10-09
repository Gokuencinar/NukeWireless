#import <UIKit/UIKit.h>
void NWCaptureDeviceAction(UIAlertAction *action, void (^handler)(UIAlertAction *));
void NWConfigureDeviceMenu(UIAlertController *menu, NSDictionary *device);
void NWInstallDeviceActionPresentation(void);
#ifdef NW_UI_TESTING
UIViewController *NWDeviceActionPresentedController(UIAlertController *menu);
int NWDeviceActionUIRegressionCheck(UIAlertController *menu);
#endif
