#import "NWTaskDiagnostics.h"
#import "NWDiagnosticReport.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

@interface NWTaskObservation : NSObject
@property(nonatomic, strong) id task;
@property(nonatomic, copy) NSDictionary *context;
@property(nonatomic, strong) NSPipe *pipe;
@property(nonatomic, strong) NSMutableData *errorBytes;
@property(nonatomic, copy) NSString *capture;
@property(atomic) BOOL expectedStop;
@property(nonatomic) BOOL truncated;
@property(nonatomic) BOOL statusWarningRecorded;
@property(nonatomic) NSTimeInterval started;
@end
@implementation NWTaskObservation
@end
static char observationKey;
static NSMutableArray<NWTaskObservation *> *observations;
static NSDictionary *actionContext;
static NSTimer *poller;
static BOOL contract(id task, NSString *name, const char *result, NSUInteger count) {
    NSMethodSignature *signature = [task methodSignatureForSelector:NSSelectorFromString(name)];
    return signature && signature.numberOfArguments == count && strchr(result, signature.methodReturnType[0]) &&
        (count != 3 || [signature getArgumentTypeAtIndex:2][0] == '@');
}
int NWTaskDiagnosticRunning(id task) {
    if (!contract(task, @"isRunning", "Bc", 2)) return -1;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"isRunning")) ? 1 : 0; }
    @catch (NSException *exception) { (void)exception; return -1; }
}
void NWTaskDiagnosticContext(NSDictionary *context) { @synchronized (NWTaskObservation.class) { actionContext = [context copy]; } }
static NSDictionary *details(NWTaskObservation *item) {
    NSMutableDictionary *value = [item.context mutableCopy] ?: [NSMutableDictionary new];
    value[@"internet_cut_confirmed"] = @NO;
    value[@"evidence"] = @"local_task_only";
    value[@"elapsed_seconds"] = @(MAX(0, NSProcessInfo.processInfo.systemUptime - item.started));
    value[@"stderr_capture"] = item.capture ?: @"unavailable";
    value[@"stderr_is_exhaustive"] = @NO;
    @synchronized (item) {
        value[@"stderr_bytes_retained"] = @(item.errorBytes.length);
        value[@"stderr_truncated"] = @(item.truncated);
        // Export categories rather than raw tool output, which may contain peer names.
        NSString *text = [[[NSString alloc] initWithData:item.errorBytes encoding:NSUTF8StringEncoding] lowercaseString];
        NSMutableArray *categories = [NSMutableArray new];
        for (NSString *word in @[@"permission denied", @"operation not permitted", @"no such file", @"library not loaded", @"bpf", @"invalid argument", @"no such device"])
            if ([text containsString:word]) [categories addObject:word];
        value[@"stderr_categories"] = categories;
    }
    return value;
}
void NWTaskDiagnosticPrepare(id task) {
    if (!task || objc_getAssociatedObject(task, &observationKey)) return;
    NWTaskObservation *item = [NWTaskObservation new]; item.errorBytes = [NSMutableData new];
    @synchronized (NWTaskObservation.class) { item.context = actionContext ?: @{}; }
    item.capture = @"existing_redirect_preserved";
    @try {
        // Preserve the native reader and any existing redirect. Never read its pipe.
        if (NWTaskDiagnosticRunning(task) >= 0 && contract(task, @"standardError", "@", 2) && contract(task, @"setStandardError:", "v", 3)) {
            id stream = ((id (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"standardError"));
            if (!stream || stream == NSFileHandle.fileHandleWithStandardError) {
                item.pipe = [NSPipe pipe]; item.capture = @"bounded_categories";
                __weak NWTaskObservation *weakItem = item;
                item.pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
                    NWTaskObservation *strongItem = weakItem;
                    @try {
                        NSData *data = handle.availableData;
                        if (!data.length) { handle.readabilityHandler = nil; return; }
                        if (!strongItem) return;
                        @synchronized (strongItem) {
                            NSUInteger remaining = 4096 - strongItem.errorBytes.length;
                            [strongItem.errorBytes appendData:[data subdataWithRange:NSMakeRange(0, MIN(remaining, data.length))]];
                            if (data.length > remaining) strongItem.truncated = YES;
                        }
                    } @catch (NSException *exception) { (void)exception; handle.readabilityHandler = nil; }
                };
                ((void (*)(id, SEL, id))objc_msgSend)(task, NSSelectorFromString(@"setStandardError:"), item.pipe);
            }
        } else item.capture = @"runtime_contract_unavailable";
    } @catch (NSException *exception) { (void)exception; item.capture = @"capture_setup_failed"; }
    objc_setAssociatedObject(task, &observationKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void finishObservation(NWTaskObservation *item, NSString *status, NSString *error) {
    NSMutableDictionary *value = [details(item) mutableCopy];
    if (error) value[@"error_code"] = error;
    if (NWTaskDiagnosticRunning(item.task) == 0 && contract(item.task, @"terminationStatus", "i", 2)) {
        @try { value[@"exit_status"] = @(((int (*)(id, SEL))objc_msgSend)(item.task, NSSelectorFromString(@"terminationStatus"))); }
        @catch (NSException *exception) { (void)exception; }
    }
    NWDiagnosticRecord(@"wifi_block_process", status, value);
    item.pipe.fileHandleForReading.readabilityHandler = nil;
    [item.pipe.fileHandleForReading closeFile];
    objc_setAssociatedObject(item.task, &observationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    item.task = nil;
}
static void poll(void) {
    for (NWTaskObservation *item in [observations copy]) {
        int running = NWTaskDiagnosticRunning(item.task);
        if (running == 1) continue;
        // Never close a live child's diagnostic pipe when its state is unknown.
        if (running < 0 && item.pipe) {
            if (!item.statusWarningRecorded) {
                NSMutableDictionary *value = [details(item) mutableCopy]; value[@"error_code"] = @"task_status_unavailable";
                NWDiagnosticRecord(@"wifi_block_process", @"warning", value); item.statusWarningRecorded = YES;
            }
            continue;
        }
        finishObservation(item, running < 0 ? @"warning" : item.expectedStop ? @"stopped" : @"failed",
            running < 0 ? @"task_status_unavailable" : item.expectedStop ? nil : @"block_process_exited");
        [observations removeObject:item];
    }
    if (!observations.count) { [poller invalidate]; poller = nil; }
}
void NWTaskDiagnosticLaunched(id task) {
    NWTaskObservation *item = objc_getAssociatedObject(task, &observationKey);
    if (!item) return;
    item.task = task; item.started = NSProcessInfo.processInfo.systemUptime;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!observations) observations = [NSMutableArray new];
        // The caller's native registry limits active tasks to 64. Release exited
        // observations before registering a subsequent launch.
        poll();
        [observations addObject:item];
        NWDiagnosticRecord(@"wifi_block_process", @"started", details(item));
        if (!poller) poller = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { (void)timer; poll(); }];
    });
}
void NWTaskDiagnosticLaunchFailed(id task, id exception) {
    NWTaskObservation *item = objc_getAssociatedObject(task, &observationKey);
    if (!item) return;
    NSMutableDictionary *value = [item.context mutableCopy];
    value[@"error_code"] = @"task_launch_exception";
    value[@"exception_name"] = [exception isKindOfClass:NSException.class] ? [exception name] : @"unknown";
    NWDiagnosticRecord(@"wifi_block_process", @"failed", value);
    item.pipe.fileHandleForReading.readabilityHandler = nil;
    [item.pipe.fileHandleForReading closeFile];
    objc_setAssociatedObject(task, &observationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// Called before signalling the retained task, never with a detached/reused PID.
void NWTaskDiagnosticWillStop(id task) {
    NWTaskObservation *item = objc_getAssociatedObject(task, &observationKey); item.expectedStop = YES;
}
#ifdef NW_DIAGNOSTIC_TESTING
void NWTaskDiagnosticPollForTesting(void) { poll(); }
#endif
