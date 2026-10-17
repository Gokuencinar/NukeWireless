#import "NWBLELocation.h"
#import "NWBLEAdvertisement.h"
#import <UIKit/UIKit.h>

@interface NWBLELocation ()
@property(nonatomic,strong) CLLocationManager *manager;
@property(nonatomic,strong) CLLocation *latest;
@property(nonatomic) BOOL failed;
@end
#ifdef NW_UI_TESTING
// No real manager, permissions or location I/O in simulator regression.
@interface NWBLELocationFixture : NSObject
@property(nonatomic) CLAuthorizationStatus authorizationStatus;
@property(nonatomic,weak) id delegate;
@property(nonatomic) NSUInteger starts, stops;
@end
@implementation NWBLELocationFixture
- (void)startUpdatingLocation { self.starts++; }
- (void)stopUpdatingLocation { self.stops++; }
@end
int NWBLELocationUIRegressionCheck(void) {
    NWBLELocation *source = [NWBLELocation new]; source.scanning = YES;
    if (source.manager || source.observation || source.enabled) return 27;
    NWBLELocationFixture *fixture = [NWBLELocationFixture new];
    fixture.authorizationStatus = kCLAuthorizationStatusAuthorizedWhenInUse;
    source.manager = (id)fixture; source.enabled = YES;
    if (fixture.starts != 1) return 28;
    [source locationManager:(id)fixture didUpdateLocations:@[[[CLLocation alloc] initWithLatitude:40 longitude:-3]]];
    if (!source.observation) return 29;
    source.scanning = NO;
    if (source.observation || !fixture.stops) return 30;
    fixture.authorizationStatus = kCLAuthorizationStatusDenied; source.scanning = YES;
    if (source.observation || ![source.statusKey isEqual:@"ble.location_denied"] || fixture.starts != 1) return 31;
    source.enabled = NO; source.manager = nil;
    return 0;
}
#endif
@implementation NWBLELocation
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    if (enabled && !self.manager) {
        self.manager = [CLLocationManager new]; self.manager.delegate = self;
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        self.manager.distanceFilter = 10;
    }
    if (enabled && self.manager.authorizationStatus == kCLAuthorizationStatusNotDetermined)
        [self.manager requestWhenInUseAuthorization];
    [self update];
}
- (void)setScanning:(BOOL)scanning { _scanning = scanning; [self update]; }
- (void)update {
    CLAuthorizationStatus status = self.manager.authorizationStatus;
    BOOL allowed = status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways;
    if (self.enabled && self.scanning && allowed && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        self.failed = NO; [self.manager startUpdatingLocation];
    } else { [self.manager stopUpdatingLocation]; self.latest = nil; }
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager { (void)manager; [self update]; }
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager; if (!self.enabled || !self.scanning) return;
    self.latest = locations.lastObject; self.failed = NO;
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager; (void)error; self.latest = nil; self.failed = YES;
}
- (NSDictionary *)observation {
    if (!self.enabled || !self.scanning || !self.latest || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return nil;
    CLLocation *fix = self.latest;
    return NWBLEValidateObservation(@{@"latitude":@(fix.coordinate.latitude),@"longitude":@(fix.coordinate.longitude),
        @"accuracy":@(fix.horizontalAccuracy),@"time":@(fix.timestamp.timeIntervalSince1970)},NSDate.date.timeIntervalSince1970,YES);
}
- (NSString *)statusKey {
    if (!self.enabled) return @"ble.location_off";
    CLAuthorizationStatus status = self.manager.authorizationStatus;
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) return @"ble.location_denied";
    if (status == kCLAuthorizationStatusNotDetermined) return @"ble.location_permission";
    if (self.failed) return @"ble.location_error";
    if (!self.scanning) return @"ble.location_ready";
    return self.observation ? @"ble.location_active" : @"ble.location_waiting";
}
- (void)dealloc { [self.manager stopUpdatingLocation]; self.manager.delegate = nil; }
@end
