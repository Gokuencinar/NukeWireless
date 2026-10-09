#import "NWLanguage.h"
#import "NWResources.h"
#import <objc/runtime.h>
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import "NWDeviceActions.h"
#endif

static NSString *const languageKey = @"NukeWirelessLanguage";
static _Thread_local BOOL resolvingLocalization;
NSString *NWLanguageCode(void) {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:languageKey];
    if ([saved isEqualToString:@"en"] || [saved isEqualToString:@"es"]) return saved;
    NSString *system = NSLocale.preferredLanguages.firstObject;
    return [system hasPrefix:@"es"] ? @"es" : @"en";
}
BOOL NWSetLanguage(NSString *code) {
    if (![code isEqualToString:@"en"] && ![code isEqualToString:@"es"]) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:code forKey:languageKey];
    // This is an app preference, not a device-wide language change.
    [defaults setObject:@[code] forKey:@"AppleLanguages"];
    [defaults synchronize];
    return YES;
}
static NSDictionary *languageTables(void) {
    static NSDictionary *tables; static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL previous = resolvingLocalization;
        resolvingLocalization = YES;
        NSMutableDictionary *result = [NSMutableDictionary new];
        for (NSString *code in @[@"en", @"es"]) {
            NSMutableDictionary *files = [NSMutableDictionary new];
            for (NSString *name in @[@"Localizable", @"Native"]) {
                NSString *path = [NWResourceBundle().bundlePath stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.lproj/%@.strings", code, name]];
                files[name] = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
            }
            result[code] = files;
        }
        tables = result;
        resolvingLocalization = previous;
    });
    return tables;
}
NSString *NWLocalizedText(NSString *key) {
    return languageTables()[NWLanguageCode()][@"Localizable"][key] ?: key;
}
static NSString *nativeTranslation(NSString *text) {
    if (!text.length) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDictionary *tables = languageTables();
    NSDictionary *selected = tables[NWLanguageCode()][@"Native"];
    NSString *translated = selected[text] ?: selected[trimmed];
    if (!translated) {
        // The preserved RootHide UI has several Spanish captions.
        NSDictionary *spanish = tables[@"es"][@"Native"];
        for (NSString *key in spanish) {
            if ([spanish[key] isEqualToString:text]) { translated = selected[key]; break; }
        }
    }
    return translated;
}
NSString *NWNativeText(NSString *text) { return nativeTranslation(text) ?: text; }
static NSString *(*oldLocalized)(NSBundle *, SEL, NSString *, NSString *, NSString *);
static NSString *localized(NSBundle *bundle, SEL sel, NSString *key, NSString *value, NSString *table) {
    if (resolvingLocalization) return oldLocalized(bundle, sel, key, value, table);
    resolvingLocalization = YES;
    NSString *translated = bundle == NSBundle.mainBundle ? nativeTranslation(key) : nil;
    resolvingLocalization = NO;
    return translated ?: oldLocalized(bundle, sel, key, value, table);
}
#if TARGET_OS_IOS
static id (*oldAction)(id, SEL, NSString *, UIAlertActionStyle, void (^)(UIAlertAction *));
static id action(id cls, SEL sel, NSString *title, UIAlertActionStyle style, void (^handler)(UIAlertAction *)) {
    UIAlertAction *result = oldAction(cls, sel, NWNativeText(title), style, handler);
    NWCaptureDeviceAction(result, handler); return result;
}
static id (*oldAlert)(id, SEL, NSString *, NSString *, UIAlertControllerStyle);
static id alert(id cls, SEL sel, NSString *title, NSString *message, UIAlertControllerStyle style) {
    return oldAlert(cls, sel, NWNativeText(title), NWNativeText(message), style);
}
static void (*oldButton)(UIButton *, SEL, NSString *, UIControlState);
static void button(UIButton *control, SEL sel, NSString *title, UIControlState state) {
    oldButton(control, sel, NWNativeText(title), state);
}
static void (*oldBar)(UIBarItem *, SEL, NSString *);
static void bar(UIBarItem *item, SEL sel, NSString *title) { oldBar(item, sel, NWNativeText(title)); }
static void (*oldPlaceholder)(UITextField *, SEL, NSString *);
static void placeholder(UITextField *field, SEL sel, NSString *text) { oldPlaceholder(field, sel, NWNativeText(text)); }
#endif
void NWInstallLanguageHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:));
        oldLocalized = (void *)method_setImplementation(method, (IMP)localized);
#if TARGET_OS_IOS
        method = class_getClassMethod(UIAlertAction.class, @selector(actionWithTitle:style:handler:));
        oldAction = (void *)method_setImplementation(method, (IMP)action);
        method = class_getClassMethod(UIAlertController.class, @selector(alertControllerWithTitle:message:preferredStyle:));
        oldAlert = (void *)method_setImplementation(method, (IMP)alert);
        method = class_getInstanceMethod(UIButton.class, @selector(setTitle:forState:));
        oldButton = (void *)method_setImplementation(method, (IMP)button);
        method = class_getInstanceMethod(UIBarItem.class, @selector(setTitle:));
        oldBar = (void *)method_setImplementation(method, (IMP)bar);
        method = class_getInstanceMethod(UITextField.class, @selector(setPlaceholder:));
        oldPlaceholder = (void *)method_setImplementation(method, (IMP)placeholder);
#endif
    });
}
