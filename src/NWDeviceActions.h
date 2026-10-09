#import <UIKit/UIKit.h>
void NWCaptureDeviceAction(UIAlertAction *action, void (^handler)(UIAlertAction *));
void NWInstallDeviceActionPresentation(void);
#ifdef NW_UI_TESTING
UIViewController *NWDeviceActionPresentedController(UIAlertController *menu);
#endif
