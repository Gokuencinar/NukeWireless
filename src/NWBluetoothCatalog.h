#import <UIKit/UIKit.h>
UIViewController *NWBluetoothCatalogController(void);
UIViewController *NWBluetoothCatalogControllerWithEmitter(BOOL available,
    void (^emit)(NSUInteger platform, NSArray<NSNumber *> *models));
#ifdef NW_UI_TESTING
int NWBluetoothCatalogUIRegressionCheck(void);
int NWBluetoothCatalogUIRegressionPresent(int platform);
int NWBluetoothCatalogUIRegressionSinglePresent(void);
int NWBluetoothUIRegressionCatalogState(int state);
#endif
