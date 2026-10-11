#import <Foundation/Foundation.h>
#import "NWWiFiUnblock.h"
#include <arpa/inet.h>
#include <string.h>

static Class installed;
static void (*originalUnblock)(id, SEL, id);
static void (*prepareStop)(const char *);
static void (*stopOwned)(const char *);

static __thread const char *activeIP;

void NWPerformWiFiUnblock(id value, void (^original)(void)) {
    char ip[INET_ADDRSTRLEN] = {0};
    struct in_addr address;
    if ([value isKindOfClass:NSString.class] && [value length] < sizeof(ip) &&
        inet_pton(AF_INET, [value UTF8String], &address) == 1)
        strlcpy(ip, [value UTF8String], sizeof(ip));
    BOOL owner = ip[0] && stopOwned && (!activeIP || strcmp(activeIP, ip));
    const char *previous = activeIP;
    if (owner) activeIP = ip;
    @try {
        if (owner && prepareStop) prepareStop(ip);
        original();
    }
    @finally {
        @try { if (owner) stopOwned(ip); }
        @finally { activeIP = previous; }
    }
}

static void unblock(id self, SEL selector, id value) {
    NWPerformWiFiUnblock(value, ^{ originalUnblock(self, selector, value); });
}

BOOL NWInstallWiFiUnblock(Class commands, void (*prepare)(const char *), void (*stop)(const char *)) {
    if (!commands || !stop) return NO;
    if (installed) return installed == commands;
    SEL selector = sel_registerName("unblockIPWithIp:");
    Method method = class_getClassMethod(commands, selector);
    if (!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16")) return NO;
    originalUnblock = (void *)method_getImplementation(method);
    prepareStop = prepare; stopOwned = stop;
    Class meta = object_getClass(commands);
    // Add on the selected metaclass if inherited, preserving its superclass.
    if (!class_addMethod(meta, selector, (IMP)unblock, method_getTypeEncoding(method)))
        method_setImplementation(class_getClassMethod(commands, selector), (IMP)unblock);
    installed = commands;
    return YES;
}
