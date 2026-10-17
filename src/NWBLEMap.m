#import "NWBLEMap.h"
#import "NWBLEHistory.h"
#import "NWBLEAdvertisement.h"
#import "NWDiagnosticReport.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import <MapKit/MapKit.h>

@interface NWBLEPlaceAnnotation : MKPointAnnotation
@property(nonatomic) NSUInteger count;
@end
@implementation NWBLEPlaceAnnotation
@end
@interface NWBLEMapViewController : UIViewController <MKMapViewDelegate>
@property(nonatomic,strong) MKMapView *map;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic) BOOL fitted;
@property(nonatomic) NSInteger mapError;
@property(nonatomic) BOOL renderRecorded;
@end
@implementation NWBLEMapViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = NWText(@"ble.map"); self.view.backgroundColor = NWCanvasColor();
    self.map = [MKMapView new]; self.map.delegate = self;
    // Never enable showsUserLocation: location is owned only by an explicit scan.
    self.map.showsUserLocation = NO; self.map.showsCompass = YES;
    self.hint = [UILabel new]; self.hint.numberOfLines = 0;
    self.hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.hint.adjustsFontForContentSizeCategory = YES;
    self.hint.textColor = UIColor.secondaryLabelColor;
    for (UIView *part in @[self.map,self.hint]) { part.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:part]; }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.hint.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12], [self.hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.map.topAnchor constraintEqualToAnchor:self.hint.bottomAnchor constant:12], [self.map.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.map.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor], [self.map.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearPlaces)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = NWText(@"ble.map_clear");
    UIBarButtonItem *center = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"scope"] style:UIBarButtonItemStylePlain target:self action:@selector(recenter)];
    center.accessibilityLabel = NWText(@"ble.map_center");
    self.navigationItem.rightBarButtonItems = @[self.navigationItem.rightBarButtonItem,center];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:NWBLEHistoryChanged object:NWBLEHistory.shared]; [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar); [self refresh]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self recenter];
    __weak NWBLEMapViewController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if (weak.viewIfLoaded.window) [weak recordState];
    });
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self fitIfNeeded]; }
- (void)dealloc { self.map.delegate = nil; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh {
    [self.map removeAnnotations:self.map.annotations]; [self.map removeOverlays:self.map.overlays];
    NSMutableArray *annotations = [NSMutableArray new];
    NSDateFormatter *date = [NSDateFormatter new]; date.dateStyle = NSDateFormatterShortStyle; date.timeStyle = NSDateFormatterShortStyle;
    for (NSDictionary *point in NWBLEObservationPlaces(NWBLEHistory.shared.records)) {
        NWBLEPlaceAnnotation *pin = [NWBLEPlaceAnnotation new]; pin.coordinate = CLLocationCoordinate2DMake([point[@"latitude"] doubleValue],[point[@"longitude"] doubleValue]);
        pin.count = [point[@"count"] unsignedIntegerValue];
        pin.title = pin.count > 1 ? [NSString stringWithFormat:NWText(@"ble.map_group"),(unsigned long)pin.count] : ([point[@"name"] length] ? point[@"name"] : NWText(@"ble.unnamed"));
        pin.subtitle = [NSString stringWithFormat:@"%@ · ±%.0f m",[date stringFromDate:[NSDate dateWithTimeIntervalSince1970:[point[@"time"] doubleValue]]],[point[@"accuracy"] doubleValue]];
        [annotations addObject:pin];
        [self.map addOverlay:[MKCircle circleWithCenterCoordinate:pin.coordinate radius:MAX(1,[point[@"accuracy"] doubleValue])]];
    }
    [self.map addAnnotations:annotations];
    self.hint.text = NWText(annotations.count ? @"ble.map_hint" : @"ble.map_empty");
    self.navigationItem.rightBarButtonItems.firstObject.enabled = annotations.count > 0 && !NWBLEHistory.shared.loading && !NWBLEHistory.shared.storageError;
    self.navigationItem.rightBarButtonItems.lastObject.enabled = annotations.count > 0;
    [self fitIfNeeded];
}
- (void)recenter { self.fitted = NO; [self fitIfNeeded]; }
- (void)fitIfNeeded {
    if (self.map.annotations.count && !self.fitted && self.view.window && self.map.bounds.size.width > 0 && self.map.bounds.size.height > 0) {
        // Include the fix uncertainty in the fitted area, also for a single point.
        MKMapRect extent = MKMapRectNull;
        for (id<MKOverlay> overlay in self.map.overlays) extent = MKMapRectUnion(extent,overlay.boundingMapRect);
        // A precise fix is uncertainty, not a useful initial viewport size.
        // Keep at least one kilometre visible instead of overzooming to a 9 m fix.
        MKMapPoint middle = MKMapPointMake(MKMapRectGetMidX(extent),MKMapRectGetMidY(extent));
        CLLocationCoordinate2D center = MKCoordinateForMapPoint(middle);
        double side = 1000*MKMapPointsPerMeterAtLatitude(center.latitude);
        extent = MKMapRectUnion(extent,MKMapRectMake(middle.x-side/2,middle.y-side/2,side,side));
        [self.map setVisibleMapRect:extent edgePadding:UIEdgeInsetsMake(40,40,40,40) animated:NO]; self.fitted = YES;
    }
}
- (MKAnnotationView *)mapView:(MKMapView *)map viewForAnnotation:(id<MKAnnotation>)annotation {
    MKMarkerAnnotationView *view = (id)[map dequeueReusableAnnotationViewWithIdentifier:@"detection"];
    if (!view) view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"detection"];
    view.annotation = annotation; view.canShowCallout = YES; view.clusteringIdentifier = nil; view.displayPriority = MKFeatureDisplayPriorityRequired; view.markerTintColor = NWAccentColor();
    NSUInteger count = [annotation isKindOfClass:NWBLEPlaceAnnotation.class] ? ((NWBLEPlaceAnnotation *)annotation).count : 1;
    view.glyphText = count > 1 ? [NSString stringWithFormat:@"%lu",(unsigned long)count] : nil;
    view.glyphImage = count > 1 ? nil : [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"]; return view;
}
- (MKOverlayRenderer *)mapView:(MKMapView *)map rendererForOverlay:(id<MKOverlay>)overlay {
    (void)map; MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle *)overlay];
    renderer.fillColor = [NWAccentColor() colorWithAlphaComponent:.06]; renderer.strokeColor = [NWAccentColor() colorWithAlphaComponent:.25]; renderer.lineWidth = 1; return renderer;
}
- (void)recordState {
    NSUInteger visible = 0, located = 0;
    for (NSDictionary *record in NWBLEHistory.shared.records) if ([record[@"observations"] count]) located++;
    for (id<MKAnnotation> point in self.map.annotations) {
        MKAnnotationView *view = [self.map viewForAnnotation:point];
        if (view.window && !view.hidden && view.alpha > 0 && MKMapRectContainsPoint(self.map.visibleMapRect,MKMapPointForCoordinate(point.coordinate))) visible++;
    }
    NSDictionary *state = @{@"devices_with_places":@(located),@"place_count":@(self.map.annotations.count),
        @"visible_marker_count":@(visible),@"viewport_fitted":@(self.fitted),@"attached":@(self.map.window != nil),
        @"width":@(self.map.bounds.size.width),@"height":@(self.map.bounds.size.height),@"map_loading_error":@(self.mapError),
        @"history_loading":@(NWBLEHistory.shared.loading),@"history_storage_error":@(NWBLEHistory.shared.storageError)};
    [NSUserDefaults.standardUserDefaults setObject:state forKey:@"NukeWirelessBLELastMap"];
    NWDiagnosticRecord(@"ble_map",@"viewed",state);
}
- (void)mapViewDidFinishRenderingMap:(MKMapView *)map fullyRendered:(BOOL)fullyRendered {
    (void)map; if (fullyRendered && !self.renderRecorded && self.viewIfLoaded.window) { self.renderRecorded = YES; [self recordState]; }
}
- (void)mapViewDidFailLoadingMap:(MKMapView *)map withError:(NSError *)error {
    (void)map; if (self.mapError != error.code && self.viewIfLoaded.window) { self.mapError = error.code; [self recordState]; }
}
- (void)clearPlaces {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NWText(@"ble.map_clear") message:NWText(@"ble.map_clear_hint") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NWText(@"ble.map_clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [NWBLEHistory.shared clearLocations]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
UIViewController *NWBLEMapController(void) { return [NWBLEMapViewController new]; }
#ifdef NW_UI_TESTING
int NWBLEMapUIRegressionCheck(void) {
    NWBLEMapViewController *controller = (id)NWBLEMapController(); [controller loadViewIfNeeded];
    NSUInteger count = NWBLEObservationPlaces(NWBLEHistory.shared.records).count;
    if (controller.map.showsUserLocation || controller.map.annotations.count != count || controller.map.overlays.count != count) return 21;
    return 0;
}
int NWBLEMapVisibleUIRegressionCheck(UIViewController *view) {
    NWBLEMapViewController *controller = (id)view;
    // UIKit can finish a navigation attachment on the next main-loop turn,
    // even with animated:NO. Exercise that lifecycle before asserting the fit.
    NSDate *attachmentDeadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ((!controller.view.window || !controller.fitted) && attachmentDeadline.timeIntervalSinceNow > 0) {
        [controller.navigationController.view layoutIfNeeded];
        [controller.view layoutIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    }
    id<MKAnnotation> annotation = controller.map.annotations.firstObject;
    if (!annotation || !controller.fitted) {
        NSLog(@"BLE map fixture: attached=%d fitted=%d places=%lu size=%.0fx%.0f",controller.view.window != nil,controller.fitted,(unsigned long)controller.map.annotations.count,controller.map.bounds.size.width,controller.map.bounds.size.height);
        return 32;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![controller.map viewForAnnotation:annotation] && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    MKAnnotationView *marker = [controller.map viewForAnnotation:annotation];
    if (!marker.window || marker.clusteringIdentifier || marker.displayPriority != MKFeatureDisplayPriorityRequired) return 33;
    if (!MKMapRectContainsPoint(controller.map.visibleMapRect,MKMapPointForCoordinate(annotation.coordinate))) return 34;
    return 0;
}
#endif
