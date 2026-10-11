#import <Foundation/Foundation.h>
// Source-defined bridge, resolved optionally by the preserved bootstrap adapter.
void NWTaskDiagnosticContext(NSDictionary *context);
void NWTaskDiagnosticPrepare(id task);
void NWTaskDiagnosticLaunched(id task);
void NWTaskDiagnosticLaunchFailed(id task, id exception);
void NWTaskDiagnosticWillStop(id task);
// -1 means the runtime contract could not be verified; never signal such a task.
int NWTaskDiagnosticRunning(id task);
