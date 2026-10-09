#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *const NWDiagnosticChanged;
id NWDiagnosticRedact(id value);
void NWDiagnosticInitialize(void);
void NWDiagnosticRecord(NSString *test, NSString *status, NSDictionary *details);
NSDictionary *NWDiagnosticSnapshot(void);
NSURL *NWDiagnosticSaveExport(NSError **error);
void NWDiagnosticClear(void);
