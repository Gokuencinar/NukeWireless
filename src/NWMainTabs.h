#import <UIKit/UIKit.h>
void NWPrepareMainTabs(UITabBarController *tab);
void NWStyleMainTabs(UITabBarController *tab);
BOOL NWBluetoothTabSelected(UITabBarController *tab);
UITabBarController *NWFindMainTabs(UIViewController *controller);
NSDictionary *NWMainTabsPresentationSnapshot(UITabBarController *tab);
FOUNDATION_EXPORT NSString *const NWMainTabReselected;
#ifdef NW_UI_TESTING
void NWMainTabsUIRegressionUseLegacyTraits(void);
int NWMainTabsDetachedBarCheck(void);
void NWMainTabsUIRegressionSelect(UITabBarController *tab, NSInteger tag);
int NWMainTabsRegressionCheck(UITabBarController *tab, BOOL selectBluetooth);
int NWMainTabsStabilityCheck(UITabBarController *tab);
int NWMainTabsResumePrepare(UITabBarController *tab, NSInteger tag);
int NWMainTabsResumeCheck(UITabBarController *tab);
#endif
