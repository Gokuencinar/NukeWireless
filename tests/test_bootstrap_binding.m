// Run the real adapter veto and per-task ownership code against fake tasks.
// No scan, child process, privileged command, ARP frame or system hook runs.
#import <Foundation/Foundation.h>
#include <assert.h>
#include "../src/compat/NWBootstrapPaths.c"
@interface BindingTask : NSObject
@property(nonatomic,copy) NSArray *arguments;
@property(nonatomic,copy) NSString *launchPath;
@property(nonatomic) int processIdentifier;
@property(nonatomic) BOOL isRunning;
@end
@implementation BindingTask
- (void)dealloc { [_arguments release]; [_launchPath release]; [super dealloc]; }
@end
static unsigned launches;
static void assignArguments(id task,SEL cmd,id value) { (void)cmd; [task setArguments:value]; }
static void launchFixture(id task,SEL cmd) { (void)cmd; ++launches; [task setIsRunning:YES]; }
static int pidFixture(id task,SEL cmd) { (void)cmd; return [task processIdentifier]; }
static BOOL runningFixture(id task,SEL cmd) { (void)cmd; return [task isRunning]; }
static void bind(BindingTask *task,const char *ip,const char *mac) {
    struct active_block value={0}; snprintf(value.ip,sizeof value.ip,"%s",ip);
    snprintf(value.real_mac,sizeof value.real_mac,"%s",mac);
    objc_setAssociatedObject(task,&task_binding_key,[NSData dataWithBytes:&value length:sizeof value],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    task.arguments=@[@"arpoison"]; task.launchPath=@"fixture-helper";
}
int main(void) { @autoreleasepool {
    original_arguments=assignArguments; original_launch=launchFixture;
    original_task_pid=pidFixture; original_task_running=runningFixture;
    BindingTask *first=[[[BindingTask alloc] init] autorelease]; first.processIdentifier=101;
    patched_arguments(first,NULL,@[@"arpoison",@"-i",@"en0",@"-s",@"192.0.2.42",@"-r",@"not-a-mac"]);
    assert(objc_getAssociatedObject(first,&task_rejection_key));
    patched_launch(first,NULL); assert(!launches && patched_task_pid(first,NULL)==0 && !patched_task_running(first,NULL));
    // Reconfiguration removes the old veto; another task cannot steal binding.
    patched_arguments(first,NULL,@[@"unrelated-command"]);
    assert(!objc_getAssociatedObject(first,&task_rejection_key));
    BindingTask *second=[[[BindingTask alloc] init] autorelease]; second.processIdentifier=102;
    bind(first,"192.0.2.42","02:11:22:33:44:55");
    bind(second,"192.0.2.43","02:11:22:33:44:66");
    patched_launch(second,NULL); patched_launch(first,NULL);
    assert(launches==2 && blocks[0].pid==102 && blocks[1].pid==101);
    assert(!strcmp(blocks[0].ip,"192.0.2.43") && !strcmp(blocks[1].ip,"192.0.2.42"));
    assert(!strcmp(blocks[0].real_mac,"02:11:22:33:44:66") && !strcmp(blocks[1].real_mac,"02:11:22:33:44:55"));
    assert(!objc_getAssociatedObject(first,&task_binding_key) && !objc_getAssociatedObject(second,&task_binding_key));
    for(unsigned i=0;i<64;++i) { [blocks[i].task release]; memset(&blocks[i],0,sizeof blocks[i]); }
    puts("PASS: rejected task sends nothing, PID/state veto and interleaved per-task binding ownership");
} }
