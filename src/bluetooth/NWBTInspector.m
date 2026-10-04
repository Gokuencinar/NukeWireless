#import "NWBTBridge.h"
#import "NWBTNative.h"
#import <OSLog/OSLog.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

static void cancelPing(int signalNumber) {
    if (NWBTCancelled) _exit(128 + signalNumber);
    NWBTCancelled = 1;
    alarm(3); // Allow bounded link cleanup, then force termination if stalled.
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        BOOL ping = argc == 4 && !strcmp(argv[1], "--l2ping") && !strcmp(argv[3], "--exclusive");
        BOOL skywalk = argc == 3 && !strcmp(argv[1], "--skywalk-open") && !strcmp(argv[2], "--exclusive");
        BOOL skywalkInfo = argc == 3 && !strcmp(argv[1], "--skywalk-info") && !strcmp(argv[2], "--exclusive");
        BOOL controller = ping || skywalk || skywalkInfo || (argc == 3 && !strcmp(argv[1], "--controller-info") && !strcmp(argv[2], "--exclusive"));
        if (!controller && (argc != 2 || (strcmp(argv[1], "--inspect") && strcmp(argv[1], "--transport-code")))) {
            fputs("Usage: nwbt-inspect --inspect | --transport-code | --controller-info --exclusive | --skywalk-open --exclusive | --skywalk-info --exclusive | --l2ping ADDRESS --exclusive\nExclusive access requires Bluetooth off in Settings. Only --l2ping connects to a remote target (five bounded echoes).\n", stderr);
            return 64;
        }
        NSError *error = nil;
        if (controller) alarm(20); // Bound a stalled private driver call to this helper process.
        if (ping) {
            signal(SIGINT, cancelPing); signal(SIGTERM, cancelPing); signal(SIGALRM, cancelPing);
            alarm(23);
        }
        if (controller) fputs("NWBT phase: diagnostic started\n", stderr);
        NSDate *start = [NSDate dateWithTimeIntervalSinceNow:-1.0];
        NSDictionary *report = ping ? NWBTL2Ping([NSString stringWithUTF8String:argv[2]]) : skywalkInfo ? NWBTReadSkywalkController() : skywalk ? NWBTOpenSkywalk() : controller ? NWBTReadControllerInfo() :
            (!strcmp(argv[1], "--transport-code") ? NWBTCopyTransportCode() : NWBTInspectTransport());
        if (controller) fputs("NWBT phase: diagnostic returned\n", stderr);
        const char *collectLogs = getenv("NWBT_PROCESS_LOGS");
        if (controller && report[@"error"] && collectLogs && !strcmp(collectLogs, "1")) {
            // Public API, restricted to this helper's own process. The log
            // command is absent on the device; do not request system log access.
            OSLogStore *store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:&error];
            NSMutableDictionary *details = [report mutableCopy];
            if (store) {
                OSLogEnumerator *entries = [store entriesEnumeratorWithOptions:0
                    position:[store positionWithDate:start] predicate:nil error:&error];
                NSMutableArray *messages = [NSMutableArray new];
                NSUInteger seen = 0;
                double deadline = NSProcessInfo.processInfo.systemUptime + 1.0;
                for (OSLogEntry *entry in entries) {
                    if (++seen > 200 || NSProcessInfo.processInfo.systemUptime > deadline) break;
                    NSString *message = entry.composedMessage;
                    if (message.length > 1000) message = [message substringToIndex:1000];
                    if (message.length) [messages addObject:message];
                    if (messages.count >= 30) break;
                }
                details[@"process_diagnostics"] = messages;
            }
            if (error) details[@"diagnostics_error"] = error.localizedDescription;
            report = details;
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        if (controller) alarm(0);
        return report[@"error"] ? 1 : 0;
    }
}
