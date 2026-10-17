#import "NWBLEAdvertisement.h"
#include <math.h>

static NSString *boundedText(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || text.length > limit || [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    return text;
}
NSDictionary *NWBLEValidateObservation(id input, double referenceTime, BOOL fresh) {
    if (![input isKindOfClass:NSDictionary.class] || !isfinite(referenceTime) || referenceTime <= 0) return nil;
    for (NSString *key in @[@"latitude",@"longitude",@"accuracy",@"time"])
        if (![input[key] isKindOfClass:NSNumber.class] || !isfinite([input[key] doubleValue])) return nil;
    double lat=[input[@"latitude"] doubleValue], lon=[input[@"longitude"] doubleValue];
    double accuracy=[input[@"accuracy"] doubleValue], time=[input[@"time"] doubleValue];
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180 || accuracy < 0 || accuracy > 5000 || time <= 0 ||
        time > referenceTime+1 || (fresh && referenceTime-time > 10)) return nil;
    return @{@"latitude":@(lat),@"longitude":@(lon),@"accuracy":@(accuracy),@"time":@(time)};
}
NSArray<NSString *> *NWBLEServiceLabels(NSArray *services) {
    // UUID evidence only. Names, company IDs and RSSI never establish device identity.
    NSDictionary *known = @{@"180A":@"ble.service_information",@"180D":@"ble.service_heart",
        @"180F":@"ble.service_battery",@"1812":@"ble.service_hid",@"181A":@"ble.service_environment",@"FE2C":@"ble.service_fastpair"};
    NSMutableOrderedSet *labels = [NSMutableOrderedSet new];
    for (id value in services) {
        if (![value isKindOfClass:NSString.class]) continue;
        NSString *uuid = [value uppercaseString];
        if (uuid.length == 36 && [uuid hasPrefix:@"0000"] && [uuid hasSuffix:@"-0000-1000-8000-00805F9B34FB"])
            uuid = [uuid substringWithRange:NSMakeRange(4,4)];
        if (known[uuid]) [labels addObject:known[uuid]];
    }
    return labels.array;
}
NSArray<NSDictionary *> *NWBLESignalSamples(NSArray *previous, NSInteger rssi, double time) {
    if (!isfinite(time) || time < 0) return previous ?: @[];
    NSMutableArray *samples = [NSMutableArray new]; double last = -1;
    for (id item in previous) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"time"] isKindOfClass:NSNumber.class] || ![item[@"rssi"] isKindOfClass:NSNumber.class]) continue;
        double t = [item[@"time"] doubleValue], r = [item[@"rssi"] doubleValue];
        if (!isfinite(t) || t < last || t > time || !isfinite(r) || r < -127 || r > 20) continue;
        [samples addObject:@{@"time":@(t),@"rssi":@(r)}]; last = t;
        if (samples.count > 60) [samples removeObjectAtIndex:0];
    }
    if (rssi >= -127 && rssi <= 20) {
        if (samples.count && time - [samples.lastObject[@"time"] doubleValue] < .5)
            samples[samples.count-1] = @{@"time":samples.lastObject[@"time"],@"rssi":@(rssi)};
        else [samples addObject:@{@"time":@(time),@"rssi":@(rssi)}];
    }
    if (samples.count > 60) [samples removeObjectAtIndex:0];
    return [samples copy];
}
BOOL NWBLEMatchesFilter(NSDictionary *record, NSString *text, NSInteger filter) {
    if (filter == 1 && ![record[@"name"] length]) return NO;
    if (filter == 2 && ![record[@"connectable"] boolValue]) return NO;
    NSString *query = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return YES;
    NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@",record[@"name"] ?: @"",record[@"company"] ?: @"",
        record[@"identifier"] ?: @"",[record[@"services"] componentsJoinedByString:@" "] ?: @""];
    return [haystack rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location != NSNotFound;
}

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
    record[@"firstSeen"] = previous[@"firstSeen"] ?: @(seen);
    record[@"advertisements"] = @([previous[@"advertisements"] unsignedIntegerValue] + 1);
    record[@"samples"] = NWBLESignalSamples(previous[@"samples"],rssi,seen);
    return [record copy];
}

NSDictionary *NWBLEHistoryRecord(NSDictionary *previous, NSDictionary *advertisement, double wallTime) {
    NSString *identifier = boundedText(advertisement[@"identifier"],36);
    if (!identifier.length || ![[NSUUID alloc] initWithUUIDString:identifier] || !isfinite(wallTime) || wallTime <= 0) return nil;
    NSMutableDictionary *record = previous ? [previous mutableCopy] : [NSMutableDictionary new];
    record[@"identifier"] = identifier;
    for (NSString *key in @[@"name",@"company"]) {
        NSString *text = boundedText(advertisement[key],128); if (text) record[key] = text;
    }
    NSMutableOrderedSet *services = [NSMutableOrderedSet new];
    for (id value in advertisement[@"services"]) {
        NSString *service = boundedText(value,64); if (service && services.count < 32) [services addObject:service];
    }
    record[@"services"] = services.array;
    if ([advertisement[@"connectable"] isKindOfClass:NSNumber.class]) record[@"connectable"] = @([advertisement[@"connectable"] boolValue]);
    NSInteger rssi = [advertisement[@"rssi"] isKindOfClass:NSNumber.class] ? [advertisement[@"rssi"] integerValue] : 127;
    if (rssi >= -127 && rssi <= 20) record[@"rssi"] = @(rssi); else [record removeObjectForKey:@"rssi"];
    double first = [previous[@"firstSeen"] doubleValue], last = [previous[@"seen"] doubleValue];
    record[@"firstSeen"] = @(first > 0 ? MIN(first,wallTime) : wallTime);
    record[@"seen"] = @(MAX(last,wallTime));
    record[@"advertisements"] = @(MIN((NSUInteger)1000000000,[previous[@"advertisements"] unsignedIntegerValue] + 1));
    record[@"samples"] = NWBLESignalSamples(previous[@"samples"],rssi,MAX(last,wallTime));
    NSMutableArray *points = [NSMutableArray new];
    if ([previous[@"observations"] isKindOfClass:NSArray.class]) for (id item in previous[@"observations"]) {
        NSDictionary *point = NWBLEValidateObservation(item,MAX(last,wallTime),NO);
        if (point) [points addObject:point];
        if (points.count > 8) [points removeObjectAtIndex:0];
    }
    NSDictionary *point = NWBLEValidateObservation(advertisement[@"observation"],wallTime,YES);
    if (point && (!points.count || [point[@"time"] doubleValue]-[points.lastObject[@"time"] doubleValue] >= 10)) [points addObject:point];
    if (points.count > 8) [points removeObjectAtIndex:0];
    if (points.count) record[@"observations"] = points; else [record removeObjectForKey:@"observations"];
    // Raw manufacturer/service payloads are never persisted.
    return record;
}
NSArray<NSDictionary *> *NWBLEValidateHistory(id input) {
    if (![input isKindOfClass:NSArray.class] || [input count] > 200) return @[];
    NSMutableArray *records = [NSMutableArray new]; NSMutableSet *seen = [NSMutableSet new];
    for (id item in input) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"seen"] isKindOfClass:NSNumber.class] ||
            ![item[@"firstSeen"] isKindOfClass:NSNumber.class] || ![item[@"advertisements"] isKindOfClass:NSNumber.class] ||
            ![item[@"services"] isKindOfClass:NSArray.class] || [item[@"services"] count] > 32 ||
            ![item[@"samples"] isKindOfClass:NSArray.class] || [item[@"samples"] count] > 60) continue;
        double last = [item[@"seen"] doubleValue], first = [item[@"firstSeen"] doubleValue], count = [item[@"advertisements"] doubleValue];
        if (!isfinite(first) || first <= 0 || !isfinite(last) || last < first || !isfinite(count) || count < 1 || count > 1000000000) continue;
        NSDictionary *clean = NWBLEHistoryRecord(nil,item,last);
        if (!clean || [seen containsObject:clean[@"identifier"]]) continue;
        NSMutableDictionary *record = [clean mutableCopy];
        record[@"firstSeen"] = @(first); record[@"advertisements"] = @((NSUInteger)count);
        record[@"samples"] = NWBLESignalSamples(item[@"samples"],127,last);
        NSMutableArray *points = [NSMutableArray new];
        if ([item[@"observations"] isKindOfClass:NSArray.class] && [item[@"observations"] count] <= 8) {
            double previousTime = 0;
            for (id inputPoint in item[@"observations"]) {
                NSDictionary *point = NWBLEValidateObservation(inputPoint,last,NO);
                if (point && [point[@"time"] doubleValue] >= previousTime) { [points addObject:point]; previousTime = [point[@"time"] doubleValue]; }
            }
        }
        if (points.count) record[@"observations"] = points;
        [seen addObject:record[@"identifier"]]; [records addObject:record];
    }
    return records;
}
