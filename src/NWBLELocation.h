#import <CoreLocation/CoreLocation.h>
// Foreground scan-only location. No manager or permission prompt until enabled.
@interface NWBLELocation : NSObject <CLLocationManagerDelegate>
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL scanning;
@property(nonatomic,readonly) NSString *statusKey;
- (NSDictionary *)observation;
@end
