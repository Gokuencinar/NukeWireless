#import <Foundation/Foundation.h>
NSString *NWLanguageCode(void);
BOOL NWSetLanguage(NSString *code);
NSString *NWLocalizedText(NSString *key);
NSString *NWNativeText(NSString *text);
void NWInstallLanguageHooks(void);
