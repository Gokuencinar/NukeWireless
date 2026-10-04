#import "NWBTBridge.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || (strcmp(argv[1], "--inspect") && strcmp(argv[1], "--transport-code"))) {
            fputs("Usage: nwbt-inspect --inspect | --transport-code\nRead-only inspection; no Bluetooth packets are sent.\n", stderr);
            return 64;
        }
        NSError *error = nil;
        NSDictionary *report = !strcmp(argv[1], "--transport-code") ? NWBTCopyTransportCode() : NWBTInspectTransport();
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        return report[@"error"] ? 1 : 0;
    }
}
