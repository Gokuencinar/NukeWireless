#import "NWBLEAdvertisement.h"

NSString *NWBLEManufacturer(NSData *data) {
    if (data.length < 2) return nil;
    const uint8_t *bytes = data.bytes;
    unsigned company = bytes[0] | (bytes[1] << 8);
    // Company IDs describe the advertisement, not authenticated device identity.
    NSString *name;
    switch (company) {
        case 0x004C: name = @"Apple"; break;
        case 0x0075: name = @"Samsung"; break;
        case 0x0006: name = @"Microsoft"; break;
        case 0x00E0: name = @"Google"; break;
        default: name = nil; break;
    }
    return name ? [NSString stringWithFormat:@"%@ (0x%04X)", name, company] :
        [NSString stringWithFormat:@"0x%04X", company];
}

NSDictionary *NWBLEUpdateRecord(NSDictionary *previous, NSString *identifier,
    NSString *name, NSInteger rssi, NSData *manufacturer, NSArray<NSString *> *services,
    NSNumber *connectable, double seen) {
    NSMutableDictionary *record = previous ? [previous mutableCopy] : [NSMutableDictionary new];
    record[@"identifier"] = identifier;
    if (name.length) record[@"name"] = [name copy];
    // 127 is the controller's unavailable RSSI sentinel, not a strong signal.
    if (rssi >= -127 && rssi <= 20) record[@"rssi"] = @(rssi);
    else [record removeObjectForKey:@"rssi"];
    if (manufacturer) {
        record[@"manufacturer"] = [manufacturer copy];
        NSString *company = NWBLEManufacturer(manufacturer);
        if (company) record[@"company"] = company;
        else [record removeObjectForKey:@"company"];
    }
    if (services) {
        NSMutableOrderedSet *merged = [NSMutableOrderedSet orderedSetWithArray:record[@"services"] ?: @[]];
        [merged addObjectsFromArray:services];
        record[@"services"] = merged.array;
    }
    if (connectable) record[@"connectable"] = connectable;
    record[@"seen"] = @(seen);
    return [record copy];
}
