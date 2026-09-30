#import "../src/NWResources.h"
#import "../src/NWLanguage.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSDictionary *table = NWParseVendorText(@"00-11-22   (hex)   Example Inc.\r\nAA-BB-CC (hex) Other Vendor\n00-11-22 (base 16) ignored\ninvalid\n");
    assert(table.count == 2);
    assert([table[@"001122"] isEqualToString:@"Example Inc."]);
    assert(NWParseVendorText(nil).count == 0);
    assert(NWParseVendorText(@"<html>error</html>").count == 0);
    NSArray *args = @[@"/usr/bin/arpoison",@"-w",@"0.9",@"-t",@"192.168.1.2"];
    NSArray *changed = NWPacketArguments(args,nil,1.3);
    assert([changed[2] isEqualToString:@"1.3"]);
    assert([changed[4] isEqualToString:args[4]]);
    assert([args[2] isEqualToString:@"0.9"]);
    assert([NWPacketArguments(@[@"-w",@"1"],@"/usr/bin/arpoison",0.4)[1] isEqualToString:@"0.4"]);
    NSArray *repair = [args arrayByAddingObjectsFromArray:@[@"-n",@"3"]];
    assert(NWPacketArguments(repair,nil,2) == repair);
    NSArray *other = @[@"echo",@"arpoison.txt",@"-w",@"1"];
    assert(NWPacketArguments(other,nil,2) == other);
    NSArray *missing = @[@"arpoison",@"-w"];
    assert(NWPacketArguments(missing,nil,2) == missing);
    assert(NWPacketArguments(nil,nil,2) == nil);
    assert(NWSetLanguage(@"es"));
    assert([NWLanguageCode() isEqualToString:@"es"]);
    assert([NWText(@"refresh") isEqualToString:@"Actualizar"]);
    assert([NWNativeText(@"Block Device") isEqualToString:@"Bloquear equipo"]);
    assert([NWNativeText(@"192.168.1.1") isEqualToString:@"192.168.1.1"]);
    assert([NWNativeText(@"Apple, Inc.") isEqualToString:@"Apple, Inc."]);
    assert(!NWSetLanguage(@"fr"));
    assert([NWLanguageCode() isEqualToString:@"es"]);
    assert(NWSetLanguage(@"en"));
    assert([NWText(@"refresh") isEqualToString:@"Refresh"]);
    assert([NWNativeText(@"Nombres") isEqualToString:@"Names"]);
    NWInstallLanguageHooks();
    assert([[NSBundle.mainBundle localizedStringForKey:@"Rename Device" value:nil table:nil] isEqualToString:@"Rename device"]);
    assert(NWSetLanguage(@"es"));
    assert([[NSBundle.mainBundle localizedStringForKey:@"Rename Device" value:nil table:nil] isEqualToString:@"Cambiar nombre del equipo"]);
    assert([[NSUserDefaults.standardUserDefaults arrayForKey:@"AppleLanguages"] isEqualToArray:@[@"es"]]);
    puts("PASS: explicit language, persistence, native captions and raw network data");
    puts("PASS: OUI parsing, malformed data, packet interval routing, repair and unrelated tasks unchanged");
} return 0; }
