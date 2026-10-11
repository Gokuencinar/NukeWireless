#import "../src/NWTaskDiagnostics.h"
#import "../src/NWDiagnosticReport.h"
#include <assert.h>
#include <stdio.h>
extern void NWDiagnosticUseTestDirectory(NSURL *url);
extern void NWDiagnosticFlushForTesting(void);
extern void NWTaskDiagnosticPollForTesting(void);
static void drain(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    NWTaskDiagnosticPollForTesting();
}
static NSDictionary *last(void) { return [NWDiagnosticSnapshot()[@"events"] lastObject]; }
int main(void) {
    @autoreleasepool {
        NSURL *folder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        NWDiagnosticUseTestDirectory(folder);
        NWTaskDiagnosticContext(@{@"operation_id": @"wifi-1", @"peer_tag": @"peer-1"});
        NSTask *task = [NSTask new]; task.launchPath = @"/bin/sh";
        task.arguments = @[@"-c", @"printf 'permission denied 192.168.1.42 private-name\\n' >&2; exit 7"];
        NWTaskDiagnosticPrepare(task); assert([task.standardError isKindOfClass:NSPipe.class]);
        [task launch]; NWTaskDiagnosticLaunched(task); [task waitUntilExit]; drain();
        NSDictionary *event = last(), *details = event[@"details"];
        assert([event[@"status"] isEqual:@"failed"] && [details[@"exit_status"] isEqual:@7]);
        assert([details[@"operation_id"] isEqual:@"wifi-1"] && ![details[@"internet_cut_confirmed"] boolValue]);
        assert([details[@"stderr_categories"] containsObject:@"permission denied"]);
        assert(![details.description containsString:@"private-name"] && ![details.description containsString:@"192.168"]);
        assert(NWTaskDiagnosticRunning(task) == 0);

        task = [NSTask new]; task.launchPath = @"/bin/sleep"; task.arguments = @[@"10"];
        NSPipe *existing = [NSPipe pipe]; task.standardError = existing;
        NWTaskDiagnosticPrepare(task); assert(task.standardError == existing);
        [task launch]; NWTaskDiagnosticLaunched(task); assert(NWTaskDiagnosticRunning(task) == 1);
        NWTaskDiagnosticWillStop(task); [task terminate]; [task waitUntilExit]; drain();
        assert([last()[@"status"] isEqual:@"stopped"]);
        assert([last()[@"details"][@"stderr_capture"] isEqual:@"existing_redirect_preserved"]);

        task = [NSTask new]; task.launchPath = @"/no-such-nukewireless-test-binary";
        NWTaskDiagnosticPrepare(task);
        @try { [task launch]; assert(0); }
        @catch (NSException *exception) { NWTaskDiagnosticLaunchFailed(task, exception); }
        assert([last()[@"details"][@"error_code"] isEqual:@"task_launch_exception"]);
        NSObject *unsupported = [NSObject new]; NWTaskDiagnosticPrepare(unsupported); NWTaskDiagnosticLaunched(unsupported); drain();
        assert(NWTaskDiagnosticRunning(unsupported) == -1);
        assert([last()[@"details"][@"error_code"] isEqual:@"task_status_unavailable"]);
        NWDiagnosticFlushForTesting();
        assert([NSFileManager.defaultManager removeItemAtURL:folder error:NULL]);
        puts("task diagnostics: real child exit, stderr privacy, existing reader, expected stop, launch failure, unsupported contract passed");
    }
}
