#import "NWBTBridge.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        BOOL controller = argc == 3 && !strcmp(argv[1], "--controller-info") && !strcmp(argv[2], "--exclusive");
        if (!controller && (argc != 2 || (strcmp(argv[1], "--inspect") && strcmp(argv[1], "--transport-code")))) {
            fputs("Usage: nwbt-inspect --inspect | --transport-code | --controller-info --exclusive\nController diagnostic requires Bluetooth off in Settings. No remote Bluetooth packets are sent.\n", stderr);
            return 64;
        }
        NSError *error = nil;
        if (controller) alarm(20); // Bound a stalled private driver call to this helper process.
        NSDictionary *report = controller ? NWBTReadControllerInfo() :
            (!strcmp(argv[1], "--transport-code") ? NWBTCopyTransportCode() : NWBTInspectTransport());
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        if (controller) alarm(0);
        return report[@"error"] ? 1 : 0;
    }
}
