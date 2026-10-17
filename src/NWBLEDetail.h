#import <UIKit/UIKit.h>
UIViewController *NWBLEDetailController(NSDictionary *(^record)(void), BOOL historical,
    BOOL (^scanning)(void), dispatch_block_t stop);
