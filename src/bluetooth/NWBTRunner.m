#import "NWBTBridge.h"
#include "../NWCatalogProfiles.h"
#import "NWBTNative.h"
#include "NWBTControl.h"
#include "NWBTService.h"
#include <dlfcn.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <grp.h>

static const char *service = "user/501/com.apple.bluetoothd";
static const char *serviceDomain = "user/501";
static NSString *bootstrapRoot;
static BOOL recordAppRun;
static uid_t invokingUID;
static pid_t invokingParent;
static atomic_bool restoringService;
static char *const cleanEnvironment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", NULL};
static double uptime(void) { return NSProcessInfo.processInfo.systemUptime; }
static void cancelRun(int number) {
    if (NWBTCancelled) _exit(128 + number);
    NWBTCancelled = 1; alarm(4);
}
static void cancelFromApp(void) {
    // Do not depend on signal dispositions/masks inherited from UIKit or changed
    // by loaded frameworks. The radio loop observes this lock-free shared flag.
    atomic_store(&NWBTCancelled, 1);
    if (!atomic_load(&restoringService)) alarm(4);
}
static BOOL installCancellationSignals(void) {
    if (signal(SIGINT, cancelRun) == SIG_ERR || signal(SIGTERM, cancelRun) == SIG_ERR ||
        signal(SIGALRM, cancelRun) == SIG_ERR) return NO;
    sigset_t signals; sigemptyset(&signals);
    sigaddset(&signals, SIGINT); sigaddset(&signals, SIGTERM); sigaddset(&signals, SIGALRM);
    return pthread_sigmask(SIG_UNBLOCK, &signals, NULL) == 0;
}
static void finishAppControl(NSMutableDictionary *report, NWBTCancellationMonitor *monitor) {
    NWBTStopCancellationMonitor(monitor);
    BOOL requested = atomic_load(&monitor->requested);
    report[@"cancellation_requested_via_app_channel"] = @(requested);
    uint64_t start = atomic_load(&monitor->requested_at_ns), end = NWBTControlMonotonicNS();
    if (requested && start && end >= start) report[@"app_cancel_to_report_seconds"] = @((end - start) / 1e9);
    if (NWBTCancelled && !report[@"error_code"]) {
        report[@"error_code"] = @"cancelled"; report[@"error"] = @"Diagnostic cancelled.";
    }
}

static NSDictionary *errorReport(NSString *code) {
    return @{@"version": NWBT_VERSION, @"error_code": code, @"stage": @"runner", @"l2ping_verified": @NO};
}
static int printReport(NSDictionary *report) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
    if (!json) return 1;
    // Only an admitted explicit diagnostic writes this bounded root-owned record.
    // No target address is included; status queries and recovery leave it intact.
    if (recordAppRun && bootstrapRoot && json.length <= 65536) {
        NSData *record = [NSJSONSerialization dataWithJSONObject:@{@"report": report,
            @"caller_uid": @(invokingUID), @"parent_pid": @(invokingParent)} options:0 error:NULL];
        NSString *path = [bootstrapRoot stringByAppendingPathComponent:@"var/run/nukewireless-bluetooth-app.json"];
        int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
        struct stat info;
        if (descriptor >= 0 && !fstat(descriptor, &info) && S_ISREG(info.st_mode) &&
            info.st_uid == 0 && !(info.st_mode & 0077) && !ftruncate(descriptor, 0)) {
            const uint8_t *bytes = record.bytes; NSUInteger offset = 0;
            while (offset < record.length) {
                ssize_t count = write(descriptor, bytes + offset, record.length - offset);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) break; offset += (NSUInteger)count;
            }
        }
        if (descriptor >= 0) close(descriptor);
    }
    fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
    return report[@"error"] || report[@"error_code"] ? 1 : 0;
}

// libproc.h and the original app's aegis helper use this exact signature.
// Both paths must resolve under the same physical bootstrap. No suffix-only
// caller check, PATH lookup, shell command or caller-supplied executable.
static BOOL callerAllowed(char ownPath[PATH_MAX]) {
    int (*pidpath)(int, void *, uint32_t) = dlsym(RTLD_DEFAULT, "proc_pidpath");
    if (!pidpath) {
        void *library = dlopen("/usr/lib/libproc.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (library) pidpath = dlsym(library, "proc_pidpath");
    }
    char raw[PATH_MAX] = {0}, parentRaw[PATH_MAX] = {0}, parent[PATH_MAX] = {0};
    if (!pidpath || pidpath(getpid(), raw, sizeof(raw)) <= 0 || !realpath(raw, ownPath)) return NO;
    struct stat info;
    if (lstat(ownPath, &info) || !S_ISREG(info.st_mode) || info.st_uid || (info.st_mode & 0022)) return NO;
    if (getuid() == 0) return YES; // Explicit root operator / independent recovery.
    if (getuid() != 501) return NO;
    pid_t parentPID = getppid();
    if (parentPID <= 1 || pidpath(parentPID, parentRaw, sizeof(parentRaw)) <= 0 || !realpath(parentRaw, parent)) return NO;
    const char *suffix = "/usr/bin/nwbt-run";
    if (strlen(ownPath) < strlen(suffix)) return NO;
    size_t rootLength = strlen(ownPath) - strlen(suffix);
    if (strcmp(ownPath + rootLength, suffix)) return NO;
    char expected[PATH_MAX];
    int count = snprintf(expected, sizeof(expected), "%.*s/Applications/HarpyReloaded.app/HarpyReloaded", (int)rootLength, ownPath);
    if (count < 0 || count >= (int)sizeof(expected) || strcmp(parent, expected) || getppid() != parentPID) return NO;
    return !lstat(parent, &info) && S_ISREG(info.st_mode) && info.st_uid == 0 && !(info.st_mode & 0022);
}

// Each launchctl invocation has its own deadline and bounded output. This
// also prevents a stuck restore command from keeping the recovery process alive.
static int control(const char *verb, const char *argument, NSString **output) {
    int descriptors[2]; if (pipe(descriptors)) return -1;
    fcntl(descriptors[0], F_SETFL, O_NONBLOCK);
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, descriptors[0]);
    posix_spawn_file_actions_addclose(&actions, descriptors[1]);
    NSString *executable = [bootstrapRoot stringByAppendingPathComponent:@"bin/launchctl"];
    char *arguments[] = {(char *)executable.fileSystemRepresentation, (char *)verb, (char *)argument, NULL, NULL};
    if (!strcmp(verb, "bootstrap")) {
        arguments[2] = (char *)serviceDomain; arguments[3] = (char *)argument;
    }
    pid_t child = 0;
    int result = posix_spawn(&child, executable.fileSystemRepresentation, &actions, NULL, arguments, cleanEnvironment);
    posix_spawn_file_actions_destroy(&actions); close(descriptors[1]);
    if (result) { close(descriptors[0]); return -result; }
    NSMutableData *data = [NSMutableData new]; double deadline = uptime() + 3.0;
    BOOL exited = NO, overflow = NO; int status = 0;
    while (uptime() < deadline) {
        char buffer[2048]; ssize_t count;
        while ((count = read(descriptors[0], buffer, sizeof(buffer))) > 0) {
            if (data.length + (NSUInteger)count > 65536) { overflow = YES; break; }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        if (overflow) break;
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) { exited = YES; break; }
        if (waited < 0 && errno != EINTR) { if (errno == ECHILD) { exited = YES; status = -1; } break; }
        struct pollfd descriptor = {descriptors[0], POLLIN, 0}; poll(&descriptor, 1, 20);
    }
    if (!exited) { kill(child, SIGKILL); while (waitpid(child, &status, 0) < 0 && errno == EINTR) {} }
    // A final nonblocking drain collects output produced just before exit.
    char buffer[2048]; ssize_t count;
    while ((count = read(descriptors[0], buffer, sizeof(buffer))) > 0 && data.length + (NSUInteger)count <= 65536)
        [data appendBytes:buffer length:(NSUInteger)count];
    close(descriptors[0]);
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return exited && !overflow && WIFEXITED(status) ? WEXITSTATUS(status) : -1000;
}

static BOOL running(void) {
    NSString *state = nil;
    NSString *prefix = [[NSString stringWithUTF8String:service] stringByAppendingString:@" = {"];
    return control("print", service, &state) == 0 && [state hasPrefix:prefix] &&
        [state containsString:@"\n\tstate = running\n"];
}
static BOOL selectService(void) {
    // Inspect both fixed domains without changing either. Refuse ambiguity.
    int selected = -1;
    for (unsigned i = 0; i < 2; ++i) {
        service = NWBTServiceLabel(i); serviceDomain = NWBTServiceDomain(i);
        if (!running()) continue;
        if (selected >= 0) return NO;
        selected = (int)i;
    }
    if (selected < 0) return NO;
    service = NWBTServiceLabel((unsigned)selected); serviceDomain = NWBTServiceDomain((unsigned)selected);
    return YES;
}
// Observe availability only: no frames, HCI commands or service mutations.
// bluetoothd can be running before its HCI nexus is republished. EBUSY means
// the published channel belongs to the restored service, which is expected.
static NSDictionary *waitForInterface(BOOL cleanup, NSUInteger *attempts) {
    double deadline = uptime() + 5.0;
    NSDictionary *result;
    *attempts = 0;
    do {
        if (!cleanup && NWBTCancelled) return errorReport(@"cancelled");
        NSDictionary *error = nil; uint64_t capacity = 0;
        void *channel = NWBTOpenNativeChannel(@"hci", &capacity, &error);
        ++*attempts;
        if (channel) {
            NWBTCloseNativeChannel(channel);
            return @{@"stage": @"skywalk_opened", @"remote_bluetooth_packets_sent": @0};
        }
        result = error ?: errorReport(@"transport");
        if ([result[@"stage"] isEqual:@"skywalk_open"] && [result[@"system_errno"] intValue] == EBUSY) return result;
        if (![result[@"interface_pending"] boolValue] || uptime() >= deadline) return result;
        usleep(100000);
    } while (uptime() < deadline);
    return result;
}
static BOOL interfaceReady(NSDictionary *result) {
    return [result[@"stage"] isEqual:@"skywalk_opened"] ||
        ([result[@"stage"] isEqual:@"skywalk_open"] && [result[@"system_errno"] intValue] == EBUSY);
}
static BOOL restoreService(void) {
    // A live, enabled service is already restored; don't restart it twice.
    if (!running()) {
        int status = control("bootstrap", "/rootfs/System/Library/LaunchDaemons/com.apple.bluetoothd.plist", NULL);
        if (status) control("bootstrap", "/System/Library/LaunchDaemons/com.apple.bluetoothd.plist", NULL);
    }
    if (control("enable", service, NULL)) return NO;
    control("kickstart", service, NULL);
    double deadline = uptime() + 3.0;
    do { if (running()) return YES; usleep(100000); } while (uptime() < deadline);
    return NO;
}

static int recover(void) {
    struct stat pipeInfo, lockInfo, handshake;
    if (getuid() || fstat(3, &pipeInfo) || !S_ISFIFO(pipeInfo.st_mode) ||
        fstat(4, &lockInfo) || !S_ISREG(lockInfo.st_mode) || lockInfo.st_uid || (lockInfo.st_mode & 0077) ||
        fstat(5, &handshake) || !S_ISFIFO(handshake.st_mode)) return 1;
    signal(SIGPIPE, SIG_IGN);
    if (write(5, "y", 1) != 1) return 1;
    close(5);
    // Before arming, EOF or timeout means no service mutation was authorized.
    struct pollfd descriptor = {3, POLLIN | POLLHUP, 0}; char byte = 0;
    if (poll(&descriptor, 1, 5000) <= 0 || read(3, &byte, 1) != 1 || byte != 'a') return 0;
    // This child survives app/worker exit and owns the inherited flock until
    // restoration finishes. EOF, completion or process termination restores.
    if (poll(&descriptor, 1, -1) > 0) read(3, &byte, 1);
    BOOL restored = restoreService(); close(3); close(4);
    return restored ? 0 : 1;
}

static pid_t startRecovery(const char *ownPath, int lock, int *writer) {
    int descriptors[2]; if (pipe(descriptors)) return -1;
    int reader = fcntl(descriptors[0], F_DUPFD_CLOEXEC, 10);
    int inheritedLock = fcntl(lock, F_DUPFD_CLOEXEC, 10);
    close(descriptors[0]);
    if (reader < 0 || inheritedLock < 0) {
        if (reader >= 0) close(reader); if (inheritedLock >= 0) close(inheritedLock); close(descriptors[1]); return -1;
    }
    fcntl(descriptors[1], F_SETFD, FD_CLOEXEC);
    int handshake[2];
    if (pipe(handshake)) { close(reader); close(inheritedLock); close(descriptors[1]); return -1; }
    int ackWriter = fcntl(handshake[1], F_DUPFD_CLOEXEC, 10);
    close(handshake[1]);
    if (ackWriter < 0) { close(handshake[0]); close(reader); close(inheritedLock); close(descriptors[1]); return -1; }
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, reader, 3);
    posix_spawn_file_actions_adddup2(&actions, inheritedLock, 4);
    posix_spawn_file_actions_adddup2(&actions, ackWriter, 5);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    posix_spawnattr_t attributes; posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSID);
    char *arguments[] = {(char *)ownPath, "--recover", (char *)serviceDomain, NULL}; pid_t child = -1;
    int status = posix_spawn(&child, ownPath, &actions, &attributes, arguments, cleanEnvironment);
    posix_spawnattr_destroy(&attributes); posix_spawn_file_actions_destroy(&actions);
    close(reader); close(inheritedLock); close(ackWriter);
    struct pollfd ready = {handshake[0], POLLIN, 0}; char acknowledgement = 0;
    BOOL confirmed = !status && poll(&ready, 1, 5000) > 0 && read(handshake[0], &acknowledgement, 1) == 1 && acknowledgement == 'y';
    close(handshake[0]);
    if (!confirmed) { close(descriptors[1]); if (!status) { kill(child, SIGKILL); waitpid(child, NULL, 0); } return -1; }
    *writer = descriptors[1]; return child;
}

static NSString *codeForReport(NSDictionary *report) {
    NSString *stage = report[@"stage"], *message = report[@"error"];
    if ([report[@"connection_hci_status"] unsignedIntegerValue] == 0x04) return @"page_timeout";
    if ([stage isEqual:@"abi"]) return @"unsupported";
    if ([stage isEqual:@"bluetooth_state"]) return @"bluetooth_off";
    if ([stage isEqual:@"bluetooth_state_unavailable"]) return @"bluetooth_unavailable";
    if ([stage isEqual:@"permissions"]) return @"permissions";
    if ([message containsString:@"pairing"]) return @"pairing";
    if ([message containsString:@"Connection failed"] || [message containsString:@"Target connection timed out"]) return @"connection";
    if ([message containsString:@"cancelled"]) return @"cancelled";
    if ([message containsString:@"No matching L2CAP"]) return @"no_echo";
    return @"transport";
}

static NSDictionary *runExclusive(NSString *address, const char *ownPath, NSUInteger count, NSUInteger intervalMS, BOOL lab, BOOL applePairing, BOOL fastPair, NSUInteger multiPlatform, NSUInteger catalogPlatform, NSArray<NSNumber *> *catalogModels) {
    // Reject invalid options before guard, lock acquisition or service changes.
    if (address && !NWBTPingMillisecondsValid(count, intervalMS)) return errorReport(@"arguments");
    // The older ACL diagnostic still uses the device-specific legacy ABI.
    // Reject it before manager initialization or any service mutation.
    NSDictionary *guard = address ? NWBTLegacyCompatibility() : NWBTNativeAvailability();
    if (!guard) guard = NWBTVerifyBluetoothOff();
    if (!guard) guard = NWBTNativeGuard();
    if (guard) { NSMutableDictionary *report = [guard mutableCopy]; report[@"error_code"] = codeForReport(guard); return report; }
    NSString *lockPath = [bootstrapRoot stringByAppendingPathComponent:@"var/run/nukewireless-bluetooth.lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    struct stat info;
    if (lock < 0 || fstat(lock, &info) || !S_ISREG(info.st_mode) || info.st_uid || (info.st_mode & 0077) || flock(lock, LOCK_EX | LOCK_NB)) {
        if (lock >= 0) close(lock); return errorReport(@"busy");
    }
    int writer = -1; pid_t recovery = -1; BOOL armed = NO;
    NSString *preflightStage = nil;
    NSMutableDictionary *report = nil;
    @try {
        if (!selectService()) return errorReport(@"service");
        NSString *disabled = nil, *state = nil;
        int initialStatus = control("print", service, &state);
        NSString *prefix = [[NSString stringWithUTF8String:service] stringByAppendingString:@" = {"];
        if (initialStatus || ![state hasPrefix:prefix] || ![state containsString:@"\n\tstate = running\n"]) {
            NSMutableDictionary *details = [errorReport(@"service") mutableCopy];
            details[@"service_exit"] = @(initialStatus); details[@"service_output"] = [state substringToIndex:MIN(state.length, 1024)] ?: @"";
            return details;
        }
        if (control("print-disabled", serviceDomain, &disabled) ||
            [disabled containsString:@"\"com.apple.bluetoothd\" => disabled"] || [disabled containsString:@"\"com.apple.bluetoothd\" => true"])
            return errorReport(@"service");
        NSUInteger attempts = 0;
        NSDictionary *preflight = waitForInterface(NO, &attempts);
        preflightStage = preflight[@"stage"];
        // The app can open/close this validated channel while bluetoothd is
        // running; SSH sees EBUSY instead. Both observed outcomes permit the
        // guarded retirement below. No frames are consumed in this preflight.
        if (!interfaceReady(preflight)) {
            NSMutableDictionary *details = [errorReport(@"exclusive") mutableCopy];
            if (NWBTCancelled) details[@"error_code"] = @"cancelled";
            details[@"exclusive_phase"] = @"preflight";
            details[@"preflight"] = preflight;
            details[@"interface_probe_attempts"] = @(attempts);
            return details;
        }
        // The user may change the power state during the bounded wait.
        NSDictionary *currentGuard = NWBTNativeGuard();
        if (currentGuard) {
            NSMutableDictionary *details = [currentGuard mutableCopy];
            details[@"error_code"] = codeForReport(currentGuard);
            return details;
        }
        recovery = startRecovery(ownPath, lock, &writer);
        if (recovery <= 0) return errorReport(@"recovery");
        if (write(writer, "a", 1) != 1) return errorReport(@"recovery");
        armed = YES;
        if (control("bootout", service, NULL)) report = [errorReport(@"service") mutableCopy];
        else {
            double deadline = uptime() + 3.0; NSString *state = nil; int status = 0;
            do { status = control("print", service, &state); if (status) break; usleep(100000); } while (uptime() < deadline && !NWBTCancelled);
            if (!status || ![state containsString:@"Could not find service"]) {
                report = [errorReport(@"exclusive") mutableCopy];
                report[@"exclusive_phase"] = @"service_retirement";
                report[@"service_exit"] = @(status);
                report[@"service_output"] = [state substringToIndex:MIN(state.length, 1024)] ?: @"";
            }
            else if (NWBTCancelled) report = [errorReport(@"cancelled") mutableCopy];
            else report = [(address ? NWBTL2PingWithMilliseconds(address, count, intervalMS) : lab ?
                (catalogModels ? NWBTAdvertiseCatalogLab(catalogPlatform, catalogModels) : multiPlatform ? NWBTAdvertiseMultiDeviceLab(multiPlatform) : fastPair ? NWBTAdvertiseFastPairLab() : applePairing ? NWBTAdvertiseApplePairingLab() : NWBTAdvertiseSwiftPairLab()) : NWBTReadLECapabilities()) mutableCopy];
        }
    } @catch (NSException *exception) {
        (void)exception; report = [errorReport(@"transport") mutableCopy];
    } @finally {
        atomic_store(&restoringService, YES);
        // A late Stop still marks cancellation but cannot truncate readiness
        // checks after the advertisement has already stopped.
        alarm(26);
        if (writer >= 0) { if (armed) write(writer, "r", 1); close(writer); }
        if (recovery > 0) {
            int status = 0; BOOL exited = NO; double deadline = uptime() + 18.0;
            // Service recovery owns cancellation from here. A hard worker exit
            // still leaves the independent child alive holding the lock.
            while (uptime() < deadline) {
                if (waitpid(recovery, &status, WNOHANG) == recovery) { exited = YES; break; }
                usleep(50000);
            }
            if (armed && report) {
                BOOL restored = exited && WIFEXITED(status) && WEXITSTATUS(status) == 0;
                report[@"service_restored"] = @(restored);
                if (restored) {
                    NSUInteger attempts = 0; double started = uptime();
                    NSDictionary *readiness = waitForInterface(YES, &attempts);
                    report[@"controller_interface_ready"] = @(interfaceReady(readiness));
                    report[@"recovery_interface_probe_attempts"] = @(attempts);
                    report[@"recovery_interface_wait_seconds"] = @(uptime() - started);
                    if (!interfaceReady(readiness)) {
                        report[@"recovery_interface"] = readiness;
                        report[@"cleanup_warning"] = @"Bluetooth service is running but its controller interface is not ready.";
                        report[@"error_code"] = @"recovery";
                    }
                }
            }
        }
        close(lock);
    }
    if (!report) report = [errorReport(@"transport") mutableCopy];
    report[@"radio_state_verified_before_exclusive"] = @YES;
    report[@"service_domain"] = [NSString stringWithUTF8String:serviceDomain];
    if (preflightStage) report[@"preflight_stage"] = preflightStage;
    if (NWBTCancelled) { report[@"error"] = @"Diagnostic cancelled."; report[@"error_code"] = @"cancelled"; }
    if (report[@"error"] && !report[@"error_code"]) report[@"error_code"] = codeForReport(report);
    if (armed && (![report[@"service_restored"] boolValue] ||
        (report[@"controller_interface_ready"] && ![report[@"controller_interface_ready"] boolValue]))) report[@"error_code"] = @"recovery";
    return report;
}

static BOOL decimalOption(const char *text, NSUInteger *value) {
    if (!text || !*text || strlen(text) > 9) return NO;
    NSUInteger parsed = 0;
    for (const char *p = text; *p; ++p) {
        if (*p < '0' || *p > '9') return NO;
        parsed = parsed * 10 + (NSUInteger)(*p - '0');
    }
    *value = parsed; return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        invokingUID = getuid(); invokingParent = getppid();
        BOOL milliseconds = argc == 5 && !strcmp(argv[1], "--ping-ms");
        recordAppRun = milliseconds || ((argc == 3 || argc == 5) && !strcmp(argv[1], "--ping"));
        BOOL recovery = argc == 3 && !strcmp(argv[1], "--recover");
        if (recovery) {
            int index = NWBTServiceDomainIndex(argv[2]);
            if (index < 0) return printReport(errorReport(@"arguments"));
            service = NWBTServiceLabel((unsigned)index); serviceDomain = NWBTServiceDomain((unsigned)index);
        }
        BOOL capabilities = argc == 2 && !strcmp(argv[1], "--le-capabilities");
        BOOL swiftPair = argc == 2 && !strcmp(argv[1], "--le-swift-pair-test");
        BOOL applePairing = argc == 2 && !strcmp(argv[1], "--le-apple-pairing-test");
        BOOL fastPair = argc == 2 && !strcmp(argv[1], "--le-fast-pair-test");
        BOOL catalog = argc > 1 && !strcmp(argv[1], "--le-catalog-test");
        NSUInteger catalogPlatform = 0; NSArray<NSNumber *> *catalogModels = nil;
        if (catalog) {
            unsigned selected[NW_CATALOG_SELECTION];
            if (argc != 4 || strlen(argv[2]) != 1 || argv[2][0] < '0' || argv[2][0] >= '0' + NW_CATALOG_PLATFORMS)
                return printReport(errorReport(@"arguments"));
            catalogPlatform = (NSUInteger)(argv[2][0] - '0');
            size_t count = NWCatalogProfileParse(argv[3], (unsigned)catalogPlatform, selected);
            if (!count) return printReport(errorReport(@"arguments"));
            NSMutableArray *models = [NSMutableArray new];
            for (size_t i = 0; i < count; ++i) [models addObject:@(selected[i])];
            catalogModels = [models copy];
        }
        NSUInteger multiPlatform = argc!=2 ? 0 : !strcmp(argv[1], "--le-multi-windows-test") ? 1 :
            !strcmp(argv[1], "--le-multi-apple-test") ? 2 : !strcmp(argv[1], "--le-multi-android-test") ? 3 : 0;
        BOOL lab = swiftPair || applePairing || fastPair || multiPlatform || catalog;
        // callerAllowed below admits only root or the exact installed app parent.
        recordAppRun = recordAppRun || capabilities || lab;
        if (recovery && getuid() != 0) return printReport(errorReport(@"permissions"));
        char ownPath[PATH_MAX] = {0};
        if (!callerAllowed(ownPath) || geteuid() || setgroups(0, NULL) || setgid(0) || setuid(0))
            return printReport(errorReport(@"permissions"));
        NSString *physical = [NSString stringWithUTF8String:ownPath];
        NSString *suffix = @"/usr/bin/nwbt-run";
        if (![physical hasSuffix:suffix]) return printReport(errorReport(@"permissions"));
        bootstrapRoot = [physical substringToIndex:physical.length - suffix.length];
        signal(SIGPIPE, SIG_IGN);
        signal(SIGCHLD, SIG_DFL);
        if (recovery) return recover();
        if (capabilities || lab) {
            if (!installCancellationSignals()) return printReport(errorReport(@"transport"));
            alarm(60);
            NWBTCancellationMonitor monitor;
            if (NWBTStartCancellationMonitor(&monitor, STDIN_FILENO, cancelFromApp) < 0) {
                alarm(0);
                return printReport(errorReport(@"transport"));
            }
            NSMutableDictionary *report = [runExclusive(nil, ownPath, 0, 0, lab, applePairing, fastPair, multiPlatform, catalogPlatform, catalogModels) mutableCopy];
            finishAppControl(report, &monitor);
            alarm(0); return printReport(report);
        }
        if (argc == 2 && !strcmp(argv[1], "--status")) {
            NSDictionary *information = NWBTInspectTransport();
            BOOL reference = [information[@"machine"] isEqual:@"iPhone11,2"] && [information[@"ios"] isEqual:@"16.3.1"];
            NSDictionary *compatibility = NWBTNativeAvailability();
            BOOL supported = !compatibility;
            return printReport(@{@"version": NWBT_VERSION, @"supported": @(supported), @"available": @YES,
                @"native_admission_policy": @"skywalk-runtime-contract-v1",
                @"reference_device": @(reference),
                @"compatibility": compatibility ?: @{@"stage": @"runtime_admitted"},
                @"supports_ping_options": @(reference), @"supports_ping_milliseconds": @(reference),
                @"supports_le_capability_reads": @YES, @"supports_le_capability_app": @YES,
                @"supports_app_cancel_channel": @YES,
                @"supports_le_catalog_test": @YES, @"supports_le_catalog_identity_v2": @YES,
                @"supports_le_catalog_six_models": @YES,
                @"supports_le_catalog_extended_models": @YES,
                @"supports_le_swift_pair_test": @YES,
                @"supports_le_apple_pairing_test": @YES, @"supports_le_fast_pair_test": @YES, @"supports_le_multi_device_test": @YES});
        }
        if (!milliseconds && ((argc != 3 && argc != 5) || strcmp(argv[1], "--ping"))) return printReport(errorReport(@"arguments"));
        NSUInteger count = NWBT_DEFAULT_COUNT, intervalMS = milliseconds ? NWBT_DEFAULT_INTERVAL_MS : NWBT_DEFAULT_INTERVAL;
        if (argc == 5 && (!decimalOption(argv[3], &count) || !decimalOption(argv[4], &intervalMS)))
            return printReport(errorReport(@"arguments"));
        if (!milliseconds) {
            if (!NWBTPingOptionsValid(count, intervalMS)) return printReport(errorReport(@"arguments"));
            intervalMS *= 1000;
        }
        if (!NWBTPingMillisecondsValid(count, intervalMS)) return printReport(errorReport(@"arguments"));
        NSString *address = [NSString stringWithUTF8String:argv[2]];
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\\z" options:0 error:NULL];
        if (!address || ![pattern firstMatchInString:address options:0 range:NSMakeRange(0, address.length)] ||
            [address isEqual:@"00:00:00:00:00:00"] || [address.uppercaseString isEqual:@"FF:FF:FF:FF:FF:FF"])
            return printReport(errorReport(@"address"));
        if (!installCancellationSignals()) return printReport(errorReport(@"transport"));
        unsigned int timeout = (unsigned int)((count * (intervalMS / 1000.0)) + 60);
        alarm(timeout > 60 ? timeout : 60);
        NWBTCancellationMonitor monitor;
        if (NWBTStartCancellationMonitor(&monitor, STDIN_FILENO, cancelFromApp) < 0) {
            alarm(0);
            return printReport(errorReport(@"transport"));
        }
        NSMutableDictionary *report = [runExclusive(address.uppercaseString, ownPath, count, intervalMS, NO, NO, NO, 0, 0, nil) mutableCopy];
        finishAppControl(report, &monitor);
        alarm(0); return printReport(report);
    }
}
