#import "NWDiagnosticReport.h"
#import "NWBuild.h"

NSString *const NWDiagnosticChanged = @"NukeWirelessDiagnosticChanged";
static NSMutableArray *events;
static NSMutableDictionary *pending;
static NSString *session;
static NSObject *guard;
static dispatch_queue_t writer;
static const NSUInteger maximumEvents = 64;
#ifdef NW_DIAGNOSTIC_TESTING
static NSURL *testDirectory;
void NWDiagnosticUseTestDirectory(NSURL *url) { testDirectory = url; }
#endif

static id redact(id value, NSUInteger depth) {
    if (depth > 8) return @"[depth limit]";
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary new];
        NSUInteger count = 0;
        for (id key in value) {
            if (![key isKindOfClass:NSString.class] || ++count > 80) continue;
            NSString *lower = [key lowercaseString];
            BOOL secret = NO;
            for (NSString *word in @[@"password", @"secret", @"token", @"serial", @"udid", @"code_base64"])
                if ([lower containsString:word]) secret = YES;
            if ([@[@"ssid", @"bssid", @"ip", @"mac", @"hostname", @"target_address", @"nonce"] containsObject:lower]) secret = YES;
            id item = value[key];
            // Product image UUIDs identify builds, not devices or peripherals.
            BOOL buildUUID = [lower isEqual:@"macho_uuid"] && [item isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:item];
            result[[key substringToIndex:MIN((NSUInteger)100, [key length])]] = secret ? @"[redacted]" : buildUUID ? item : redact(item, depth + 1);
        }
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray new];
        for (NSUInteger i = 0; i < MIN((NSUInteger)80, [value count]); ++i) [result addObject:redact(value[i], depth + 1)];
        return result;
    }
    if ([value isKindOfClass:NSString.class]) {
        NSString *result = [value substringToIndex:MIN((NSUInteger)2048, [value length])];
        // Defense in depth for error strings and deliberately entered observations.
        for (NSString *pattern in @[@"(?i)\\b[0-9a-f]{2}(?::[0-9a-f]{2}){5}\\b", @"\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b",
                @"(?i)(?<![0-9a-z])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.]*(?:%[0-9a-z]+)?",
                @"(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b",
                @"/(?:private/preboot|var/containers|var/mobile|private/var|var/jb|var/[^ /]*jbroot)[^\\s\\\"]*"])
            result = [[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL]
                stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@"[redacted]"];
        return result;
    }
    return [value isKindOfClass:NSNumber.class] || value == NSNull.null ? value : @"[unsupported value]";
}
id NWDiagnosticRedact(id value) { return redact(value, 0); }
static NSURL *directory(void) {
#ifdef NW_DIAGNOSTIC_TESTING
    if (testDirectory) return testDirectory;
#endif
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [documents URLByAppendingPathComponent:@"NukeWireless-Diagnostics" isDirectory:YES];
}
static NSDictionary *snapshot(void) {
    return @{@"schema_version": @1, @"product": NW_BUILD_NAME, @"build": NW_BUILD_VERSION,
        @"build_marker": @NW_BUILD_MARKER, @"session_id": session, @"generated_at": @(NSDate.date.timeIntervalSince1970),
        @"privacy": @"No serial, UDID, network names, peer names or addresses. User observations are included after redaction.",
        @"pending_tests": [pending copy], @"events": [events copy]};
}
static void persist(NSDictionary *report) {
    dispatch_async(writer, ^{
        NSURL *folder = directory();
        if (!folder || ![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL]) return;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        if (data.length <= 1024 * 1024) [data writeToURL:[folder URLByAppendingPathComponent:@"latest.json"] options:NSDataWritingAtomic error:NULL];
    });
}
void NWDiagnosticInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        guard = [NSObject new]; writer = dispatch_queue_create("app.nukewireless.diagnostics.files", DISPATCH_QUEUE_SERIAL);
        events = [NSMutableArray new]; pending = [NSMutableDictionary new]; session = NSUUID.UUID.UUIDString;
        // The old journal is bounded before parsing. Pending does not imply a crash.
        NSURL *file = [directory() URLByAppendingPathComponent:@"latest.json"];
        NSNumber *size = nil; [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        if (size.unsignedLongLongValue > 0 && size.unsignedLongLongValue <= 1024 * 1024) {
            NSData *data = [NSData dataWithContentsOfURL:file];
            id old = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if ([old isKindOfClass:NSDictionary.class] && [old[@"events"] isKindOfClass:NSArray.class])
                for (id event in old[@"events"]) {
                    if (![event isKindOfClass:NSDictionary.class] || ![event[@"test"] isKindOfClass:NSString.class] ||
                        ![event[@"status"] isKindOfClass:NSString.class] || ![event[@"time"] isKindOfClass:NSNumber.class] ||
                        ![event[@"details"] isKindOfClass:NSDictionary.class]) continue;
                    id safe = NWDiagnosticRedact(event);
                    NSData *encoded = [NSJSONSerialization dataWithJSONObject:safe options:0 error:NULL];
                    if (encoded && encoded.length <= 10000) [events addObject:safe];
                }
            if ([old isKindOfClass:NSDictionary.class] && [old[@"pending_tests"] isKindOfClass:NSDictionary.class] && [old[@"pending_tests"] count])
                [events addObject:@{@"test": @"previous_session", @"status": @"interrupted", @"time": @(NSDate.date.timeIntervalSince1970),
                    @"details": @{ @"pending_tests": NWDiagnosticRedact(old[@"pending_tests"]), @"cause": @"unknown; interruption alone is not crash evidence"}}];
        }
        while (events.count > maximumEvents) [events removeObjectAtIndex:0];
    });
}
void NWDiagnosticRecord(NSString *test, NSString *status, NSDictionary *details) {
    NWDiagnosticInitialize();
    if (!test.length || !status.length) return;
    test = [test substringToIndex:MIN((NSUInteger)100, test.length)];
    status = [status substringToIndex:MIN((NSUInteger)100, status.length)];
    NSDictionary *safe = NWDiagnosticRedact(details ?: @{});
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:safe options:0 error:NULL];
    if (!encoded || encoded.length > 8192) {
        NSMutableDictionary *summary = [@{@"truncated": @YES, @"reason": @"Event exceeds 8192 bytes"} mutableCopy];
        for (NSString *key in @[@"error", @"error_code", @"stage", @"operation", @"worker_process", @"cleanup_warning",
            @"service_restored", @"controller_interface_ready", @"capabilities_verified", @"controller_advertising_acknowledged",
            @"advertising_stopped_acknowledged", @"advertising_set_removed"]) if (safe[key]) summary[key] = safe[key];
        safe = summary;
    }
    NSDictionary *report;
    @synchronized (guard) {
        if ([status isEqual:@"running"] && pending.count < 32) pending[test] = @(NSDate.date.timeIntervalSince1970); else [pending removeObjectForKey:test];
        [events addObject:@{@"test": test, @"status": status, @"time": @(NSDate.date.timeIntervalSince1970), @"details": safe}];
        while (events.count > maximumEvents) [events removeObjectAtIndex:0];
        report = snapshot(); persist(report);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:NWDiagnosticChanged object:nil]; });
}
NSDictionary *NWDiagnosticSnapshot(void) {
    NWDiagnosticInitialize(); @synchronized (guard) { return snapshot(); }
}
NSURL *NWDiagnosticSaveExport(NSError **error) {
    NWDiagnosticInitialize(); @synchronized (guard) { NSURL *folder = directory();
    if (!folder || ![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:NWDiagnosticSnapshot() options:NSJSONWritingSortedKeys error:error];
    if (!data || data.length > 1024 * 1024) return nil;
    NSURL *file = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"NukeWireless-%@.json", NSUUID.UUID.UUIDString]];
    if (![data writeToURL:file options:NSDataWritingAtomic error:error]) return nil;
    // Only our own generated exports in our own folder, newest five retained.
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:NULL];
    NSMutableArray *exports = [NSMutableArray new];
    for (NSURL *item in files) if ([item.lastPathComponent hasPrefix:@"NukeWireless-"] && [item.pathExtension isEqual:@"json"]) [exports addObject:item];
    [exports sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *ad = nil, *bd = nil; [a getResourceValue:&ad forKey:NSURLContentModificationDateKey error:NULL];
        [b getResourceValue:&bd forKey:NSURLContentModificationDateKey error:NULL]; return [(bd ?: NSDate.distantPast) compare:ad ?: NSDate.distantPast];
    }];
    for (NSUInteger i = 5; i < exports.count; ++i) [NSFileManager.defaultManager removeItemAtURL:exports[i] error:NULL];
    return file;
    }
}
void NWDiagnosticClear(void) {
    NWDiagnosticInitialize(); @synchronized (guard) { [events removeAllObjects]; [pending removeAllObjects]; persist(snapshot()); }
    NWDiagnosticRecord(@"journal", @"cleared", @{});
}
#ifdef NW_DIAGNOSTIC_TESTING
void NWDiagnosticFlushForTesting(void) { dispatch_sync(writer, ^{}); }
#endif
