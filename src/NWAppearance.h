#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const NWAppearanceChanged;
NSString *NWAccentName(void);
BOOL NWSetAccent(NSString *name);
UIColor *NWAccentColor(void);
UIColor *NWCanvasColor(void);
UIColor *NWPanelColor(void);
void NWStyleCell(UITableViewCell *cell);
void NWStyleNavigationBar(UINavigationBar *bar);
UIViewController *NWAppearanceSettingsController(void);
