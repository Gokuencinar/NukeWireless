#import <Foundation/Foundation.h>
// Presentation-only advertisement records; IDs are CoreBluetooth UUIDs, never MACs.
NSDictionary *NWBLEUpdateRecord(NSDictionary *previous, NSString *identifier,
    NSString *name, NSInteger rssi, NSData *manufacturer, NSArray<NSString *> *services,
    NSNumber *connectable, double seen);
NSString *NWBLEManufacturer(NSData *data);
NSArray<NSDictionary *> *NWBLESignalSamples(NSArray *previous, NSInteger rssi, double time);
BOOL NWBLEMatchesFilter(NSDictionary *record, NSString *text, NSInteger filter);
NSDictionary *NWBLEHistoryRecord(NSDictionary *previous, NSDictionary *advertisement, double wallTime);
NSArray<NSDictionary *> *NWBLEValidateHistory(id input);
