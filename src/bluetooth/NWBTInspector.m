#import "NWBTBridge.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--inspect")) {
            fputs("Usage: nwbt-inspect --inspect\nCapability inspection only; no Bluetooth packets are sent.\n", stderr);
            return 64;
        }
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:NWBTInspectTransport()
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!json) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
        return 0;
    }
}
