#import "../src/NWDiagnosticReport.h"
#include <assert.h>
#include <stdio.h>
extern void NWDiagnosticUseTestDirectory(NSURL *url);
extern void NWDiagnosticFlushForTesting(void);
int main(void) {
    @autoreleasepool {
        NSURL *folder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        assert([NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
        NWDiagnosticUseTestDirectory(folder);
        NSDictionary *old = @{@"events": @[], @"pending_tests": @{@"wifi_scan": @1}};
        assert([[NSJSONSerialization dataWithJSONObject:old options:0 error:NULL] writeToURL:[folder URLByAppendingPathComponent:@"latest.json"] atomically:YES]);
        NWDiagnosticInitialize();
        assert([NWDiagnosticSnapshot()[@"events"][0][@"status"] isEqual:@"interrupted"]);
        NSString *uuid = @"00112233-4455-6677-8899-AABBCCDDEEFF";
        NSDictionary *safe = NWDiagnosticRedact(@{@"SSID": @"my-network", @"token": @"sensitive", @"macho_uuid": uuid,
            @"nested": @[@{@"MAC": @"11:22:33:44:55:66", @"error": @"192.168.1.22 fe80::1234%en0 /var/mobile/Documents/private"}], @"peripheral": uuid});
        NSString *text = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:safe options:0 error:NULL] encoding:NSUTF8StringEncoding];
        for (NSString *secret in @[@"my-network", @"sensitive", @"192.168.1.22", @"fe80::1234", @"/var/mobile", @"11:22:33:44:55:66"])
            assert(![text containsString:secret]);
        assert([safe[@"macho_uuid"] isEqual:uuid]); assert([safe[@"peripheral"] isEqual:@"[redacted]"]);
        for (unsigned i = 0; i < 80; ++i) NWDiagnosticRecord(@"fixture", @"captured", @{@"sequence": @(i)});
        assert([NWDiagnosticSnapshot()[@"events"] count] == 64);
        NWDiagnosticRecord(@"wifi_scan", @"running", @{}); assert(NWDiagnosticSnapshot()[@"pending_tests"][@"wifi_scan"]);
        NWDiagnosticRecord(@"wifi_scan", @"empty", @{}); assert(!NWDiagnosticSnapshot()[@"pending_tests"][@"wifi_scan"]);
        NSMutableDictionary *huge = [NSMutableDictionary new];
        for (unsigned i = 0; i < 80; ++i) huge[@(i).stringValue] = [@"x" stringByPaddingToLength:2048 withString:@"x" startingAtIndex:0];
        NWDiagnosticRecord(@"oversize", @"captured", huge);
        assert([NWDiagnosticSnapshot()[@"events"] lastObject][@"details"][@"truncated"]);
        for (unsigned i = 0; i < 7; ++i) {
            NSError *error = nil; NSURL *file = NWDiagnosticSaveExport(&error); assert(file && !error);
            NSData *data = [NSData dataWithContentsOfURL:file]; assert(data.length < 1024 * 1024);
            assert([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]);
        }
        unsigned exports = 0;
        for (NSURL *item in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:NULL])
            if ([item.lastPathComponent hasPrefix:@"NukeWireless-"]) ++exports;
        assert(exports == 5);
        NWDiagnosticClear(); assert([NWDiagnosticSnapshot()[@"events"] count] == 1);
        NWDiagnosticFlushForTesting();
        assert([NSFileManager.defaultManager removeItemAtURL:folder error:NULL]);
        puts("diagnostics: redaction, provenance UUID, interrupted session, bounds, pending, export, retention and clear passed");
    }
    return 0;
}
