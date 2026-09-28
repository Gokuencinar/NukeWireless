#import "NWResources.h"
#import "NWPolicy.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSDictionary<NSString *, NSString *> *vendorTable;
static BOOL updating;
static void (*oldArguments)(id, SEL, NSArray *);
NSBundle *NWResourceBundle(void) {
    static NSBundle *bundle; static dispatch_once_t once;
    dispatch_once(&once, ^{ bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"NukeWirelessResources.bundle"]]; });
    return bundle ?: NSBundle.mainBundle;
}
NSString *NWText(NSString *key) { return [NWResourceBundle() localizedStringForKey:key value:key table:nil]; }
static NSURL *vendorURL(void) {
    NSURL *root = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    return [[root URLByAppendingPathComponent:@"NukeWireless" isDirectory:YES] URLByAppendingPathComponent:@"vendors.plist"];
}
static NSDictionary *bundledVendors(void) {
    return [NSDictionary dictionaryWithContentsOfURL:[NWResourceBundle() URLForResource:@"oui_vendors" withExtension:@"plist"]] ?: @{};
}
NSString *NWVendorForMAC(NSString *mac) {
    NSCAssert(NSThread.isMainThread, @"Vendor table belongs to main");
    if (!vendorTable) vendorTable = [NSDictionary dictionaryWithContentsOfURL:vendorURL()] ?: bundledVendors();
    NSString *key = [[[mac stringByReplacingOccurrencesOfString:@":" withString:@""] stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
    return key.length >= 6 ? vendorTable[[key substringToIndex:6]] : nil;
}
NSDictionary *NWParseVendorText(NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([0-9A-F]{2})-([0-9A-F]{2})-([0-9A-F]{2})\\s+\\(hex\\)\\s+([^\\r\\n]+)" options:NSRegularExpressionAnchorsMatchLines error:NULL];
    NSMutableDictionary *table = [NSMutableDictionary new];
    for (NSTextCheckingResult *match in [regex matchesInString:text ?: @"" options:0 range:NSMakeRange(0,text.length)]) {
        NSString *key = [NSString stringWithFormat:@"%@%@%@",[text substringWithRange:[match rangeAtIndex:1]],[text substringWithRange:[match rangeAtIndex:2]],[text substringWithRange:[match rangeAtIndex:3]]];
        NSString *value = [[text substringWithRange:[match rangeAtIndex:4]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length && value.length < 512) table[key] = value;
    }
    return [table copy];
}
BOOL NWVendorUpdateBusy(void) { return updating; }
static NSError *vendorError(NSString *key) { return [NSError errorWithDomain:@"NukeWireless" code:1 userInfo:@{NSLocalizedDescriptionKey:NWText(key)}]; }
void NWUpdateVendors(void (^completion)(NSError *error)) {
    NSCAssert(NSThread.isMainThread, @"Settings actions belong to main");
    if (updating) { completion(vendorError(@"vendors.busy")); return; }
    updating = YES;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURL *url = [NSURL URLWithString:@"https://standards-oui.ieee.org/oui/oui.txt"];
    [[session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSError *failure = error; NSDictionary *parsed = nil;
        NSNumber *size = nil; [location getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        if (!failure && (((NSHTTPURLResponse *)response).statusCode != 200 || !size || size.unsignedLongLongValue > 20 * 1024 * 1024 || ![response.URL.scheme isEqualToString:@"https"])) failure = vendorError(@"vendors.invalid");
        if (!failure) {
            NSString *text = [NSString stringWithContentsOfURL:location encoding:NSUTF8StringEncoding error:&failure];
            NSDictionary *table = NWParseVendorText(text);
            if (table.count < 1000) failure = vendorError(@"vendors.invalid");
            if (!failure) {
                NSData *data = [NSPropertyListSerialization dataWithPropertyList:table format:NSPropertyListBinaryFormat_v1_0 options:0 error:&failure];
                NSURL *destination = vendorURL();
                if (data && [NSFileManager.defaultManager createDirectoryAtURL:[destination URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&failure] && [data writeToURL:destination options:NSDataWritingAtomic error:&failure]) parsed = [table copy];
            }
        }
        NSDictionary *newTable = parsed; NSError *result = failure;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (newTable) vendorTable = newTable;
            updating = NO; completion(result ?: (newTable ? nil : vendorError(@"vendors.invalid")));
        });
        [session finishTasksAndInvalidate];
    }] resume];
}
BOOL NWRestoreVendors(NSError **error) {
    if (updating) { if(error) *error = vendorError(@"vendors.busy"); return NO; }
    NSURL *url = vendorURL();
    if ([NSFileManager.defaultManager fileExistsAtPath:url.path] && ![NSFileManager.defaultManager removeItemAtURL:url error:error]) return NO;
    vendorTable = bundledVendors(); return YES;
}
double NWCurrentPacketInterval(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return NWPacketInterval([defaults objectForKey:@"packetTime"] ? [defaults doubleForKey:@"packetTime"] : 0.9);
}
void NWSetPacketInterval(double value) { [NSUserDefaults.standardUserDefaults setDouble:NWPacketInterval(value) forKey:@"packetTime"]; }
NSArray *NWPacketArguments(NSArray *arguments, NSString *path, double interval) {
    BOOL poison = [path.lastPathComponent isEqualToString:@"arpoison"], repair = NO;
    for (id arg in arguments) {
        if (![arg isKindOfClass:NSString.class]) continue;
        if ([[arg lastPathComponent] isEqualToString:@"arpoison"]) poison = YES;
        if ([arg isEqualToString:@"-n"]) repair = YES;
    }
    if (poison && !repair) {
        NSUInteger index = [arguments indexOfObject:@"-w"];
        if (index != NSNotFound && index + 1 < arguments.count) {
            NSMutableArray *updated = [arguments mutableCopy];
            updated[index + 1] = [NSString stringWithFormat:@"%.1f", NWPacketInterval(interval)];
            return updated;
        }
    }
    return arguments;
}
static void setArguments(id task, SEL sel, NSArray *arguments) {
    NSString *path = [task respondsToSelector:NSSelectorFromString(@"launchPath")] ?
        ((id (*)(id, SEL))objc_msgSend)(task, NSSelectorFromString(@"launchPath")) : nil;
    oldArguments(task, sel, NWPacketArguments(arguments, path, NWCurrentPacketInterval()));
}
void NWInstallPacketIntervalHook(void) {
    Class cls = NSClassFromString(@"NSConcreteTask") ?: NSClassFromString(@"NSTask");
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"setArguments:"));
    if (method && !oldArguments) oldArguments = (void *)method_setImplementation(method, (IMP)setArguments);
}
