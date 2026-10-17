#import "NWBLEMap.h"
#import "NWBLEHistory.h"
#import "NWBLEAdvertisement.h"
#import "NWAppearance.h"
#import "NWResources.h"
#import <MapKit/MapKit.h>

@interface NWBLEMapViewController : UIViewController <MKMapViewDelegate>
@property(nonatomic,strong) MKMapView *map;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic) BOOL fitted;
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:NWBLEHistoryChanged object:NWBLEHistory.shared]; [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; NWStyleNavigationBar(self.navigationController.navigationBar); [self refresh]; }
- (void)dealloc { self.map.delegate = nil; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refresh {
    [self.map removeAnnotations:self.map.annotations]; [self.map removeOverlays:self.map.overlays];
    NSMutableArray *annotations = [NSMutableArray new];
    NSDateFormatter *date = [NSDateFormatter new]; date.dateStyle = NSDateFormatterShortStyle; date.timeStyle = NSDateFormatterShortStyle;
    for (NSDictionary *record in NWBLEHistory.shared.records) {
        NSDictionary *point = [record[@"observations"] lastObject]; if (!point) continue;
        MKPointAnnotation *pin = [MKPointAnnotation new]; pin.coordinate = CLLocationCoordinate2DMake([point[@"latitude"] doubleValue],[point[@"longitude"] doubleValue]);
        pin.title = record[@"name"] ?: NWText(@"ble.unnamed");
        pin.subtitle = [NSString stringWithFormat:@"%@ · ±%.0f m",[date stringFromDate:[NSDate dateWithTimeIntervalSince1970:[point[@"time"] doubleValue]]],[point[@"accuracy"] doubleValue]];
        [annotations addObject:pin];
        [self.map addOverlay:[MKCircle circleWithCenterCoordinate:pin.coordinate radius:MAX(1,[point[@"accuracy"] doubleValue])]];
    }
    [self.map addAnnotations:annotations];
    self.hint.text = NWText(annotations.count ? @"ble.map_hint" : @"ble.map_empty");
    self.navigationItem.rightBarButtonItem.enabled = annotations.count > 0 && !NWBLEHistory.shared.loading;
    if (annotations.count && !self.fitted) {
        // Include the fix uncertainty in the fitted area, also for a single point.
        MKMapRect extent = MKMapRectNull;
        for (id<MKOverlay> overlay in self.map.overlays) extent = MKMapRectUnion(extent,overlay.boundingMapRect);
        [self.map setVisibleMapRect:extent edgePadding:UIEdgeInsetsMake(40,40,40,40) animated:NO]; self.fitted = YES;
    }
}
- (MKAnnotationView *)mapView:(MKMapView *)map viewForAnnotation:(id<MKAnnotation>)annotation {
    MKMarkerAnnotationView *view = (id)[map dequeueReusableAnnotationViewWithIdentifier:@"detection"];
    if (!view) view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"detection"];
    view.annotation = annotation; view.canShowCallout = YES; view.clusteringIdentifier = @"ble-places"; view.markerTintColor = NWAccentColor();
    view.glyphImage = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"]; return view;
}
- (MKOverlayRenderer *)mapView:(MKMapView *)map rendererForOverlay:(id<MKOverlay>)overlay {
    (void)map; MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle *)overlay];
    renderer.fillColor = [NWAccentColor() colorWithAlphaComponent:.06]; renderer.strokeColor = [NWAccentColor() colorWithAlphaComponent:.25]; renderer.lineWidth = 1; return renderer;
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
    NSUInteger count = 0; for (NSDictionary *record in NWBLEHistory.shared.records) if ([record[@"observations"] count]) count++;
    if (controller.map.showsUserLocation || controller.map.annotations.count != count || controller.map.overlays.count != count) return 21;
    return 0;
}
#endif
