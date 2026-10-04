#import <Foundation/Foundation.h>
// Presentation-only advertisement records; IDs are CoreBluetooth UUIDs, never MACs.
NSDictionary *NWBLEUpdateRecord(NSDictionary *previous, NSString *identifier,
    NSString *name, NSInteger rssi, NSData *manufacturer, NSArray<NSString *> *services,
    NSNumber *connectable, double seen);
NSString *NWBLEManufacturer(NSData *data);
