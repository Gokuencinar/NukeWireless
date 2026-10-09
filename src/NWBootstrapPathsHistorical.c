/* Legacy RootHide path adapter for Nuke Wireless; preserved as historical source.
 * This library is injected only into me.midnightchips.harpy-reloaded.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/route.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void *IMP;
typedef unsigned long NSUInteger;
typedef signed char BOOL;

extern Class objc_getClass(const char *name);
extern Class object_getClass(id object);
extern const char *class_getName(Class cls);
extern SEL sel_registerName(const char *name);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern Method class_getClassMethod(Class cls, SEL name);
extern IMP method_setImplementation(Method method, IMP imp);
extern id objc_msgSend(id receiver, SEL selector, ...);
extern void *popen(const char *, const char *);
extern char *fgets(char *, int, void *);
extern int pclose(void *);
extern int snprintf(char *, unsigned long, const char *, ...);
extern int open(const char *, int, ...);
extern long write(int, const void *, unsigned long);
extern int close(int);
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern void CFRelease(void *);
extern Class objc_allocateClassPair(Class superclass, const char *name, unsigned long extraBytes);
extern void objc_registerClassPair(Class cls);
extern BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);

static BOOL (*original_exists)(id, SEL, id);
static void (*original_launch_path)(id, SEL, id);
static void (*original_arguments)(id, SEL, id);
static void (*original_terminate)(id, SEL);
static void (*original_interrupt)(id, SEL);
static void (*original_launch)(id, SEL);
static void (*original_swift_unblock)(uint64_t, uint64_t);
static id (*swift_string_to_nsstring)(uint64_t, uint64_t);
static void (*original_did_appear)(id, SEL, BOOL);
static void (*original_found_device)(id, SEL, id);
static id oui_brands;
static int ui_dump_count;
static int info_overlay_added;
struct cg_point { double x, y; };
struct cg_size { double width, height; };
struct cg_rect { struct cg_point origin; struct cg_size size; };

struct active_block {
    char ip[32];
    char real_mac[32];
    int pid;
};
static struct active_block blocks[64];
static struct active_block pending_block;
static int repair_in_progress;
static int capture_root_task;
static id captured_root_task;
struct scanned_device {
    char ip[32];
    char mac[32];
};
static struct scanned_device scanned_devices[64];
static int scanned_count;
static char bulk_ips[64][32];
static int bulk_count;
static id bulk_button;
static id bulk_target;
static int bulk_confirm_count;
static time_t bulk_confirm_until;

static int starts_with(const char *value, const char *prefix) {
    if (!value) return 0;
    while (*prefix) {
        if (*value++ != *prefix++) return 0;
    }
    return 1;
}

static int contains(const char *value, const char *needle) {
    if (!value || !needle) return 0;
    for (; *value; ++value) if (starts_with(value, needle)) return 1;
    return 0;
}

static int equals(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b && *a == *b) { ++a; ++b; }
    return *a == *b;
}

static const char *utf8(id string) {
    return string ? ((const char *(*)(id, SEL))objc_msgSend)(
        string, sel_registerName("UTF8String")) : 0;
}

static id jailbreak_prefix(void);
static id string_from_utf8(const char *value);

static void debug_line(const char *label, const char *value) {
    int fd = open("/tmp/harpy_gateway_debug.log", 0x209, 0666);
    if (fd < 0) return;
    char line[512];
    int n = snprintf(line, sizeof(line), "%s: %s\n", label, value ? value : "(null)");
    if (n > 0 && n < (int)sizeof(line)) write(fd, line, (unsigned long)n);
    close(fd);
}

static int get_gateway_from_system_configuration(char *ip, unsigned long ip_size) {
    void *library = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", 1);
    if (!library) { debug_line("sc-dlopen", dlerror()); return 0; }
    id (*create)(id, id, void *, void *) = (void *)dlsym(library, "SCDynamicStoreCreate");
    id (*copy_value)(id, id) = (void *)dlsym(library, "SCDynamicStoreCopyValue");
    if (!create || !copy_value) { debug_line("sc-symbol", "missing"); return 0; }
    id store = create(0, string_from_utf8("HarpyRootHide"), 0, 0);
    if (!store) { debug_line("sc-store", "nil"); return 0; }
    id value = copy_value(store, string_from_utf8("State:/Network/Global/IPv4"));
    if (!value) { debug_line("sc-value", "nil"); CFRelease(store); return 0; }
    id router = ((id (*)(id, SEL, id))objc_msgSend)(value,
        sel_registerName("objectForKey:"), string_from_utf8("Router"));
    id primary = ((id (*)(id, SEL, id))objc_msgSend)(value,
        sel_registerName("objectForKey:"), string_from_utf8("PrimaryInterface"));
    const char *router_text = utf8(router);
    const char *primary_text = utf8(primary);
    debug_line("sc-router", router_text);
    debug_line("sc-interface", primary_text);
    int good = 0;
    if (equals(primary_text, "en0") && router_text) {
        unsigned long n = 0;
        while (((*router_text >= '0' && *router_text <= '9') || *router_text == '.') && n + 1 < ip_size)
            ip[n++] = *router_text++;
        ip[n] = 0;
        good = n >= 7;
    }
    CFRelease(value);
    CFRelease(store);
    return good;
}

static int get_mac_from_arp_table(const char *ip, char *mac, unsigned long mac_size) {
    struct in_addr wanted;
    if (inet_pton(AF_INET, ip, &wanted) != 1) return 0;
    int mib[6] = {CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO};
    size_t length = 0;
    if (sysctl(mib, 6, 0, &length, 0, 0) != 0 || !length) {
        debug_line("arp-sysctl", "size query failed");
        return 0;
    }
    char size_text[32];
    snprintf(size_text, sizeof(size_text), "%lu", (unsigned long)length);
    debug_line("arp-sysctl-size", size_text);
    void *buffer = malloc(length + 8192);
    if (!buffer) return 0;
    length += 8192;
    if (sysctl(mib, 6, buffer, &length, 0, 0) != 0) {
        debug_line("arp-sysctl", "table query failed");
        free(buffer);
        return 0;
    }
    char *cursor = buffer;
    char *end = cursor + length;
    int found = 0;
    while (cursor + sizeof(struct rt_msghdr) <= end) {
        struct rt_msghdr *message = (struct rt_msghdr *)cursor;
        if (message->rtm_msglen < sizeof(struct rt_msghdr) ||
            cursor + message->rtm_msglen > end) break;
        char *next = cursor + message->rtm_msglen;
        char *address_cursor = cursor + sizeof(struct rt_msghdr);
        struct sockaddr *destination = 0;
        struct sockaddr *gateway = 0;
        for (int index = 0; index < RTAX_MAX && address_cursor + 2 <= next; ++index) {
            if (!(message->rtm_addrs & (1 << index))) continue;
            struct sockaddr *address = (struct sockaddr *)address_cursor;
            unsigned long step = address->sa_len ? ((address->sa_len + 7) & ~7UL) : 8;
            if (address_cursor + step > next) break;
            if (index == RTAX_DST) destination = address;
            if (index == RTAX_GATEWAY) gateway = address;
            address_cursor += step;
        }
        if (destination && gateway && destination->sa_family == AF_INET &&
            gateway->sa_family == AF_LINK &&
            destination->sa_len >= sizeof(struct sockaddr_in) &&
            gateway->sa_len >= sizeof(struct sockaddr_dl)) {
            struct sockaddr_in *d = (struct sockaddr_in *)destination;
            struct sockaddr_dl *g = (struct sockaddr_dl *)gateway;
            if (d->sin_addr.s_addr == wanted.s_addr && g->sdl_alen == 6 &&
                mac_size >= 18 &&
                (char *)LLADDR(g) + 6 <= (char *)gateway + gateway->sa_len) {
                const unsigned char *bytes = (const unsigned char *)LLADDR(g);
                snprintf(mac, mac_size, "%02x:%02x:%02x:%02x:%02x:%02x",
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]);
                found = 1;
                break;
            }
        }
        cursor = next;
    }
    free(buffer);
    debug_line("arp-sysctl-mac", found ? mac : "not found");
    return found;
}

static int get_interface_mac(const char *name, char *mac, unsigned long mac_size) {
    struct ifaddrs *first = 0;
    if (getifaddrs(&first) != 0) return 0;
    int found = 0;
    for (struct ifaddrs *item = first; item; item = item->ifa_next) {
        if (!item->ifa_addr || !equals(item->ifa_name, name) ||
            item->ifa_addr->sa_family != AF_LINK) continue;
        struct sockaddr_dl *link = (struct sockaddr_dl *)item->ifa_addr;
        if (link->sdl_alen != 6 || mac_size < 18) continue;
        const unsigned char *bytes = (const unsigned char *)LLADDR(link);
        snprintf(mac, mac_size, "%02x:%02x:%02x:%02x:%02x:%02x",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]);
        found = 1;
        break;
    }
    freeifaddrs(first);
    return found;
}

static int get_interface_ip(const char *name, char *ip, unsigned long ip_size) {
    struct ifaddrs *first = 0;
    if (getifaddrs(&first) != 0) return 0;
    int found = 0;
    for (struct ifaddrs *item = first; item; item = item->ifa_next) {
        if (!item->ifa_addr || !equals(item->ifa_name, name) ||
            item->ifa_addr->sa_family != AF_INET) continue;
        struct sockaddr_in *address = (struct sockaddr_in *)item->ifa_addr;
        if (inet_ntop(AF_INET, &address->sin_addr, ip, (socklen_t)ip_size))
            found = 1;
        break;
    }
    freeifaddrs(first);
    return found;
}

static id brand_for_mac(const char *mac) {
    if (!mac) return 0;
    char prefix[7] = {0};
    int digits = 0;
    for (const char *p = mac; *p && digits < 6; ++p) {
        char c = *p;
        if (c >= 'a' && c <= 'f') c -= 32;
        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))
            prefix[digits++] = c;
    }
    if (digits != 6) return 0;
    int first = (prefix[0] <= '9' ? prefix[0] - '0' : prefix[0] - 'A' + 10) * 16 +
                (prefix[1] <= '9' ? prefix[1] - '0' : prefix[1] - 'A' + 10);
    if (first & 2) return string_from_utf8("Private MAC");
    if (!oui_brands) {
        const char *root = utf8(jailbreak_prefix());
        if (!root) return 0;
        char path[512];
        if (snprintf(path, sizeof(path),
                "%s/usr/share/harpy-reloaded-roothide/oui_vendors.plist", root)
            >= (int)sizeof(path)) return 0;
        Class dictionary = objc_getClass("NSDictionary");
        id loaded = ((id (*)(id, SEL, id))objc_msgSend)(dictionary,
            sel_registerName("dictionaryWithContentsOfFile:"),
            string_from_utf8(path));
        if (loaded) oui_brands = ((id (*)(id, SEL))objc_msgSend)(loaded,
            sel_registerName("retain"));
        debug_line("oui-loaded", loaded ? "yes" : "no");
    }
    return oui_brands ? ((id (*)(id, SEL, id))objc_msgSend)(oui_brands,
        sel_registerName("objectForKey:"), string_from_utf8(prefix)) : 0;
}

static int get_gateway(char *ip, unsigned long ip_size, char *mac, unsigned long mac_size) {
    char line[256];
    char command[256];
    char interface[32] = {0};
    ip[0] = 0;
    mac[0] = 0;
    int sc_good = get_gateway_from_system_configuration(ip, ip_size);
    debug_line("sc-good", sc_good ? "yes" : "no");
    const char *root = utf8(jailbreak_prefix());
    debug_line("root", root);
    if (!root) return 0;
    if (!sc_good) {
        if (snprintf(command, sizeof(command), "%s/usr/sbin/route -n get default 2>&1", root) >= (int)sizeof(command)) return 0;
        debug_line("route-command", command);
        void *route = popen(command, "r");
        if (!route) { debug_line("route", "popen failed"); return 0; }
        while (fgets(line, sizeof(line), route)) {
            debug_line("route-output", line);
            const char *value = 0;
            if ((value = "gateway:"), contains(line, value)) {
                const char *p = line;
                while (*p && !starts_with(p, value)) ++p;
                p += 8;
                while (*p == ' ' || *p == '\t') ++p;
                unsigned long n = 0;
                while (((*p >= '0' && *p <= '9') || *p == '.') && n + 1 < ip_size)
                    ip[n++] = *p++;
                ip[n] = 0;
            } else if ((value = "interface:"), contains(line, value)) {
                const char *p = line;
                while (*p && !starts_with(p, value)) ++p;
                p += 10;
                while (*p == ' ' || *p == '\t') ++p;
                unsigned long n = 0;
                while ((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9')) {
                    if (n + 1 < sizeof(interface)) interface[n++] = *p;
                    ++p;
                }
                interface[n] = 0;
            }
        }
        pclose(route);
        debug_line("route-ip", ip);
        debug_line("route-interface", interface);
        if (!equals(interface, "en0") || !ip[0]) return 0;
    }
    if (get_mac_from_arp_table(ip, mac, mac_size)) return 1;
    if (snprintf(command, sizeof(command), "%s/usr/sbin/arp -n %s 2>&1", root, ip) >= (int)sizeof(command)) return 0;
    debug_line("arp-command", command);
    void *arp = popen(command, "r");
    if (!arp) { debug_line("arp", "popen failed"); return 0; }
    while (fgets(line, sizeof(line), arp)) {
        debug_line("arp-output", line);
        const char *p = line;
        while (*p && !starts_with(p, " at ")) ++p;
        if (!*p) continue;
        p += 4;
        unsigned long n = 0;
        while (((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') ||
                (*p >= 'A' && *p <= 'F') || *p == ':') && n + 1 < mac_size)
            mac[n++] = *p++;
        mac[n] = 0;
        break;
    }
    pclose(arp);
    debug_line("arp-mac", mac);
    return mac[0] != 0;
}

static id string_from_utf8(const char *value) {
    Class string = objc_getClass("NSString");
    return ((id (*)(id, SEL, const char *))objc_msgSend)(
        string, sel_registerName("stringWithUTF8String:"), value);
}

static id jailbreak_prefix(void) {
    Class bundle_class = objc_getClass("NSBundle");
    id bundle = ((id (*)(id, SEL))objc_msgSend)(bundle_class, sel_registerName("mainBundle"));
    id bundle_path = ((id (*)(id, SEL))objc_msgSend)(bundle, sel_registerName("bundlePath"));
    id applications = ((id (*)(id, SEL))objc_msgSend)(
        bundle_path, sel_registerName("stringByDeletingLastPathComponent"));
    return ((id (*)(id, SEL))objc_msgSend)(
        applications, sel_registerName("stringByDeletingLastPathComponent"));
}

static int is_jailbreak_file(const char *path) {
    return starts_with(path, "/usr/libexec/harpy-reloaded/") ||
           starts_with(path, "/usr/bin/arpoison") ||
           starts_with(path, "/sbin/pfctl");
}

static id rewrite_path(id path) {
    if (!path) return path;
    const char *utf8 = ((const char *(*)(id, SEL))objc_msgSend)(
        path, sel_registerName("UTF8String"));
    if (!is_jailbreak_file(utf8)) return path;
    return ((id (*)(id, SEL, id))objc_msgSend)(
        jailbreak_prefix(), sel_registerName("stringByAppendingString:"), path);
}

static id replace_in_argument(id argument, const char *old_path) {
    id old_string = string_from_utf8(old_path);
    id new_string = rewrite_path(old_string);
    return ((id (*)(id, SEL, id, id))objc_msgSend)(
        argument, sel_registerName("stringByReplacingOccurrencesOfString:withString:"),
        old_string, new_string);
}

static id rewrite_argument(id argument) {
    if (!argument) return argument;
    const char *value = utf8(argument);
    if (starts_with(value, "/private/var/containers/Bundle/Application/.jbroot-") ||
        starts_with(value, "/var/containers/Bundle/Application/.jbroot-"))
        return argument;
    id result = replace_in_argument(argument, "/usr/libexec/harpy-reloaded/");
    result = replace_in_argument(result, "/usr/bin/arpoison");
    result = replace_in_argument(result, "/sbin/pfctl");
    return result;
}

static BOOL patched_exists(id self, SEL cmd, id path) {
    return original_exists(self, cmd, rewrite_path(path));
}

static void patched_launch_path(id self, SEL cmd, id path) {
    debug_line("task-launch-path", utf8(path));
    original_launch_path(self, cmd, rewrite_path(path));
}

static void patched_terminate(id self, SEL cmd) {
    id path = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("launchPath"));
    debug_line("task-terminate", utf8(path));
    original_terminate(self, cmd);
}

static void patched_interrupt(id self, SEL cmd) {
    id path = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("launchPath"));
    debug_line("task-interrupt", utf8(path));
    original_interrupt(self, cmd);
}

static void patched_launch(id self, SEL cmd) {
    original_launch(self, cmd);
    id launch_path = ((id (*)(id, SEL))objc_msgSend)(self,
        sel_registerName("launchPath"));
    debug_line("task-launched-path", utf8(launch_path));
    char launch_pid[32];
    snprintf(launch_pid, sizeof(launch_pid), "%d",
        ((int (*)(id, SEL))objc_msgSend)(self,
            sel_registerName("processIdentifier")));
    debug_line("task-launched-pid", launch_pid);
    id arguments = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("arguments"));
    NSUInteger count = arguments ? ((NSUInteger (*)(id, SEL))objc_msgSend)(
        arguments, sel_registerName("count")) : 0;
    int arpoison = 0;
    for (NSUInteger i = 0; i < count; ++i) {
        id item = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            arguments, sel_registerName("objectAtIndex:"), i);
        if (contains(utf8(item), "arpoison")) { arpoison = 1; break; }
    }
    if (arpoison && !repair_in_progress && pending_block.ip[0]) {
        int pid = ((int (*)(id, SEL))objc_msgSend)(
            self, sel_registerName("processIdentifier"));
        char line[96];
        snprintf(line, sizeof(line), "%s pid=%d", pending_block.ip, pid);
        debug_line("block-launched", line);
        if (pid > 0) {
            int slot = -1;
            for (int i = 0; i < 64; ++i)
                if (equals(blocks[i].ip, pending_block.ip)) { slot = i; break; }
            if (slot < 0) for (int i = 0; i < 64; ++i)
                if (!blocks[i].ip[0]) { slot = i; break; }
            if (slot >= 0) {
                blocks[slot] = pending_block;
                blocks[slot].pid = pid;
            }
        }
        memset(&pending_block, 0, sizeof(pending_block));
    }
}

static void run_as_root(const char *path, const char **args, int count) {
    Class array_class = objc_getClass("NSMutableArray");
    id array = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
        array_class, sel_registerName("arrayWithCapacity:"), (NSUInteger)count);
    for (int i = 0; i < count; ++i)
        ((void (*)(id, SEL, id))objc_msgSend)(array,
            sel_registerName("addObject:"), string_from_utf8(args[i]));
    Class task_class = objc_getClass("NSTask");
    id task = ((id (*)(id, SEL))objc_msgSend)(task_class,
        sel_registerName("alloc"));
    task = ((id (*)(id, SEL))objc_msgSend)(task,
        sel_registerName("init"));
    ((void (*)(id, SEL, id))objc_msgSend)(task,
        sel_registerName("setLaunchPath:"), string_from_utf8(path));
    ((void (*)(id, SEL, id))objc_msgSend)(task,
        sel_registerName("setArguments:"), array);
    Class commands = objc_getClass("_TtC13HarpyReloaded10MCCommands");
    captured_root_task = 0;
    capture_root_task = 1;
    if (commands)
        ((void (*)(id, SEL, id, id))objc_msgSend)(commands,
            sel_registerName("asRootWithTask:args:"), task, array);
    capture_root_task = 0;
    if (captured_root_task) {
        ((void (*)(id, SEL))objc_msgSend)(captured_root_task,
            sel_registerName("launch"));
        if (contains(path, "/kill")) {
            ((void (*)(id, SEL))objc_msgSend)(captured_root_task,
                sel_registerName("waitUntilExit"));
            char result[32];
            snprintf(result, sizeof(result), "%d",
                ((int (*)(id, SEL))objc_msgSend)(captured_root_task,
                    sel_registerName("terminationStatus")));
            debug_line("root-kill-status", result);
        }
    } else {
        debug_line("root-task", "not captured");
    }
    captured_root_task = 0;
}

static void stop_block_for_ip(const char *ip_text) {
    debug_line("unblock-ip", ip_text);
    int slot = -1;
    for (int i = 0; i < 64; ++i)
        if (equals(blocks[i].ip, ip_text)) { slot = i; break; }
    if (slot < 0 || blocks[slot].pid <= 0) {
        debug_line("unblock-pid", "missing");
        return;
    }
    char pid_text[32];
    snprintf(pid_text, sizeof(pid_text), "%d", blocks[slot].pid);
    const char *root = utf8(jailbreak_prefix());
    if (!root) return;
    char kill_path[256], poison_path[256];
    snprintf(kill_path, sizeof(kill_path), "%s/usr/bin/kill", root);
    const char *kill_args[] = {"-TERM", pid_text};
    run_as_root(kill_path, kill_args, 2);
    debug_line("unblock-kill", pid_text);
    char gateway_ip[32], gateway_mac[32];
    if (blocks[slot].real_mac[0] &&
        get_gateway(gateway_ip, sizeof(gateway_ip), gateway_mac, sizeof(gateway_mac))) {
        snprintf(poison_path, sizeof(poison_path), "%s/usr/bin/arpoison", root);
        const char *repair_args[] = {"-i", "en0", "-d", gateway_ip,
            "-s", blocks[slot].ip, "-t", gateway_mac, "-r", blocks[slot].real_mac,
            "-a", "-w", "0.2", "-n", "5"};
        repair_in_progress = 1;
        run_as_root(poison_path, repair_args, 15);
        repair_in_progress = 0;
        debug_line("unblock-repair", blocks[slot].real_mac);
    }
    memset(&blocks[slot], 0, sizeof(blocks[slot]));
}

static void patched_swift_unblock(uint64_t first, uint64_t second) {
    char raw[80];
    snprintf(raw, sizeof(raw), "%016llx %016llx",
        (unsigned long long)first, (unsigned long long)second);
    debug_line("swift-unblock-raw", raw);
    char ip[32];
    int n = 0;
    if (swift_string_to_nsstring) {
        id text = swift_string_to_nsstring(first, second);
        const char *value = utf8(text);
        while (value && n < 15 &&
            ((value[n] >= '0' && value[n] <= '9') || value[n] == '.')) {
            ip[n] = value[n];
            ++n;
        }
    }
    ip[n] = 0;
    debug_line("swift-unblock", ip);
    original_swift_unblock(first, second);
    if (n >= 7) stop_block_for_ip(ip);
}

static id block_processes_for_ip(const char *ip) {
    Class array_class = objc_getClass("NSMutableArray");
    id array = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
        array_class, sel_registerName("arrayWithCapacity:"), 2);
    for (int i = 0; i < 64; ++i) {
        if (blocks[i].pid <= 0 || (ip && !equals(blocks[i].ip, ip))) continue;
        char pid_text[32];
        snprintf(pid_text, sizeof(pid_text), "%d", blocks[i].pid);
        ((void (*)(id, SEL, id))objc_msgSend)(array,
            sel_registerName("addObject:"), string_from_utf8(pid_text));
    }
    return array;
}

static id patched_running_ip(id self, SEL cmd, id ip) {
    debug_line("running-ip", utf8(ip));
    return block_processes_for_ip(utf8(ip));
}

static id patched_running_arp(id self, SEL cmd) {
    debug_line("running-arp", "called");
    return block_processes_for_ip(0);
}

static void patched_found_device(id self, SEL cmd, id device) {
    const char *ip = utf8(((id (*)(id, SEL))objc_msgSend)(
        device, sel_registerName("ipAddress")));
    const char *name = utf8(((id (*)(id, SEL))objc_msgSend)(
        device, sel_registerName("hostname")));
    const char *mac = utf8(((id (*)(id, SEL))objc_msgSend)(
        device, sel_registerName("macAddress")));
    const char *brand = utf8(((id (*)(id, SEL))objc_msgSend)(
        device, sel_registerName("brand")));
    debug_line("scan-device-ip", ip);
    debug_line("scan-device-name", name);
    debug_line("scan-device-mac", mac);
    debug_line("scan-device-brand", brand);
    char local_ip[32] = {0};
    if (ip && get_interface_ip("en0", local_ip, sizeof(local_ip)) &&
        equals(ip, local_ip) && name && name[0] && !equals(name, "Unknown Host"))
        scanned_count = 0; /* The local entry starts a fresh Wi-Fi scan. */
    if (ip && get_interface_ip("en0", local_ip, sizeof(local_ip)) &&
        equals(ip, local_ip) && (!name || !name[0] ||
            equals(name, "Unknown Host"))) {
        debug_line("scan-device", "skipped own Wi-Fi address");
        return;
    }
    if (ip && (!name || !name[0] || equals(name, "Unknown Host"))) {
        const char *last = ip;
        for (const char *p = ip; *p; ++p) if (*p == '.') last = p + 1;
        char label[64];
        snprintf(label, sizeof(label), "Equipo .%s", last);
        ((void (*)(id, SEL, id))objc_msgSend)(device,
            sel_registerName("setHostname:"), string_from_utf8(label));
        debug_line("scan-device-label", label);
    }
    if (!brand || !brand[0] || equals(brand, "Unknown Brand")) {
        id vendor = brand_for_mac(mac);
        if (vendor) {
            ((void (*)(id, SEL, id))objc_msgSend)(device,
                sel_registerName("setBrand:"), vendor);
            debug_line("scan-device-vendor", utf8(vendor));
        }
    }
    if (ip && mac && scanned_count < 64) {
        int known = 0;
        for (int i = 0; i < scanned_count; ++i)
            if (equals(scanned_devices[i].ip, ip)) { known = 1; break; }
        if (!known) {
            snprintf(scanned_devices[scanned_count].ip, sizeof(scanned_devices[scanned_count].ip), "%s", ip);
            snprintf(scanned_devices[scanned_count].mac, sizeof(scanned_devices[scanned_count].mac), "%s", mac);
            ++scanned_count;
        }
    }
    original_found_device(self, cmd, device);
}

static void set_bulk_title(const char *title) {
    if (bulk_button)
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(bulk_button,
            sel_registerName("setTitle:forState:"), string_from_utf8(title), 0);
}

static int bulk_eligible(struct scanned_device *out, int capacity) {
    char local_ip[32] = {0}, router_ip[32] = {0}, router_mac[32] = {0};
    get_interface_ip("en0", local_ip, sizeof(local_ip));
    get_gateway(router_ip, sizeof(router_ip), router_mac, sizeof(router_mac));
    int count = 0;
    for (int i = 0; i < scanned_count && count < capacity; ++i) {
        struct scanned_device *d = &scanned_devices[i];
        if (!d->ip[0] || !d->mac[0] || equals(d->ip, local_ip) ||
            equals(d->ip, router_ip)) continue;
        out[count++] = *d;
    }
    return count;
}

static void bulk_button_tapped(id self, SEL cmd, id sender) {
    (void)self; (void)cmd; (void)sender;
    if (bulk_count) {
        for (int i = 0; i < bulk_count; ++i)
            stop_block_for_ip(bulk_ips[i]);
        bulk_count = 0;
        bulk_confirm_count = 0;
        set_bulk_title("Bloquear todos");
        debug_line("bulk-action", "unblocked");
        return;
    }
    struct scanned_device candidates[64];
    int count = bulk_eligible(candidates, 64);
    if (!count) { set_bulk_title("Sin equipos disponibles"); return; }
    time_t now = time(0);
    if (bulk_confirm_count != count || now > bulk_confirm_until) {
        char title[80];
        snprintf(title, sizeof(title), "Confirmar bloqueo (%d)", count);
        set_bulk_title(title);
        bulk_confirm_count = count;
        bulk_confirm_until = now + 10;
        return;
    }
    bulk_confirm_count = 0;
    Class commands = objc_getClass("_TtC13HarpyReloaded10MCCommands");
    if (!commands || !class_getClassMethod(commands,
        sel_registerName("blockGivenIPWithIp:targetMac:"))) {
        set_bulk_title("Bloqueo no disponible");
        return;
    }
    for (int i = 0; i < count; ++i) {
        int already_blocked = 0;
        for (int j = 0; j < 64; ++j)
            if (blocks[j].pid > 0 && equals(blocks[j].ip, candidates[i].ip))
                already_blocked = 1;
        if (already_blocked) continue;
        ((void (*)(id, SEL, id, id))objc_msgSend)(commands,
            sel_registerName("blockGivenIPWithIp:targetMac:"),
            string_from_utf8(candidates[i].ip), string_from_utf8(candidates[i].mac));
        if (bulk_count < 64) {
            snprintf(bulk_ips[bulk_count], sizeof(bulk_ips[bulk_count]), "%s", candidates[i].ip);
            ++bulk_count;
        }
    }
    set_bulk_title(bulk_count ? "Desbloquear todos" : "Sin nuevos bloqueos");
    debug_line("bulk-action", bulk_count ? "blocked" : "nothing to block");
}

static void attach_bulk_button(id view) {
    if (!view) return;
    if (!bulk_target) {
        Class target_class = objc_allocateClassPair(objc_getClass("NSObject"),
            "HarpyBulkButtonTarget", 0);
        if (!target_class) return;
        class_addMethod(target_class, sel_registerName("bulkButtonTapped:"),
            (IMP)bulk_button_tapped, "v@:@");
        objc_registerClassPair(target_class);
        bulk_target = ((id (*)(id, SEL))objc_msgSend)(target_class,
            sel_registerName("new"));
    }
    id previous = ((id (*)(id, SEL, long))objc_msgSend)(view,
        sel_registerName("viewWithTag:"), 90122);
    if (previous) { bulk_button = previous; return; }
    Class button_class = objc_getClass("UIButton");
    id button = ((id (*)(id, SEL, long))objc_msgSend)(button_class,
        sel_registerName("buttonWithType:"), 1);
    struct cg_rect bounds = ((struct cg_rect (*)(id, SEL))objc_msgSend)(view,
        sel_registerName("bounds"));
    struct cg_rect frame = {{(bounds.size.width - 186) / 2, bounds.size.height - 150}, {186, 42}};
    ((void (*)(id, SEL, struct cg_rect))objc_msgSend)(button,
        sel_registerName("setFrame:"), frame);
    ((void (*)(id, SEL, long))objc_msgSend)(button,
        sel_registerName("setTag:"), 90122);
    ((void (*)(id, SEL, id, SEL, NSUInteger))objc_msgSend)(button,
        sel_registerName("addTarget:action:forControlEvents:"), bulk_target,
        sel_registerName("bulkButtonTapped:"), 1UL << 6);
    Class color_class = objc_getClass("UIColor");
    id color = ((id (*)(id, SEL))objc_msgSend)(color_class,
        sel_registerName("systemRedColor"));
    id white = ((id (*)(id, SEL))objc_msgSend)(color_class,
        sel_registerName("whiteColor"));
    ((void (*)(id, SEL, id))objc_msgSend)(button,
        sel_registerName("setBackgroundColor:"), color);
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(button,
        sel_registerName("setTitleColor:forState:"), white, 0);
    ((void (*)(id, SEL, id))objc_msgSend)(view,
        sel_registerName("addSubview:"), button);
    bulk_button = button;
    set_bulk_title(bulk_count ? "Desbloquear todos" : "Bloquear todos");
    debug_line("bulk-button", "attached");
}

static void dump_view_tree(id view, int depth, int *remaining) {
    if (!view || depth > 20 || !*remaining) return;
    --*remaining;
    const char *class_name = class_getName(object_getClass(view));
    id label = ((id (*)(id, SEL))objc_msgSend)(view,
        sel_registerName("accessibilityLabel"));
    char line[512];
    snprintf(line, sizeof(line), "%d %s | %s", depth,
        class_name ? class_name : "?", utf8(label) ? utf8(label) : "");
    debug_line("view", line);
    if (contains(class_name, "HostingScrollView")) {
        struct cg_rect frame = ((struct cg_rect (*)(id, SEL))objc_msgSend)(
            view, sel_registerName("frame"));
        snprintf(line, sizeof(line), "x=%g y=%g w=%g h=%g",
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        debug_line("scroll-frame", line);
        id elements = ((id (*)(id, SEL))objc_msgSend)(view,
            sel_registerName("accessibilityElements"));
        NSUInteger element_count = elements ? ((NSUInteger (*)(id, SEL))objc_msgSend)(
            elements, sel_registerName("count")) : 0;
        for (NSUInteger i = 0; i < element_count && i < 80; ++i) {
            id element = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                elements, sel_registerName("objectAtIndex:"), i);
            id element_label = ((id (*)(id, SEL))objc_msgSend)(element,
                sel_registerName("accessibilityLabel"));
            debug_line("scroll-accessibility", utf8(element_label));
        }
    }
    if (contains(class_name, "TableView")) {
        id data_source = ((id (*)(id, SEL))objc_msgSend)(view,
            sel_registerName("dataSource"));
        debug_line("table-data-source", data_source ? class_getName(object_getClass(data_source)) : "nil");
        NSUInteger sections = ((NSUInteger (*)(id, SEL))objc_msgSend)(view,
            sel_registerName("numberOfSections"));
        char count_text[40];
        snprintf(count_text, sizeof(count_text), "%lu", sections);
        debug_line("table-sections", count_text);
        for (NSUInteger i = 0; i < sections && i < 12; ++i) {
            NSUInteger rows = ((NSUInteger (*)(id, SEL, NSUInteger))objc_msgSend)(
                view, sel_registerName("numberOfRowsInSection:"), i);
            snprintf(count_text, sizeof(count_text), "%lu:%lu", i, rows);
            debug_line("table-rows", count_text);
        }
    }
    id children = ((id (*)(id, SEL))objc_msgSend)(view,
        sel_registerName("subviews"));
    NSUInteger count = children ? ((NSUInteger (*)(id, SEL))objc_msgSend)(
        children, sel_registerName("count")) : 0;
    for (NSUInteger i = 0; i < count && *remaining; ++i) {
        id child = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            children, sel_registerName("objectAtIndex:"), i);
        dump_view_tree(child, depth + 1, remaining);
    }
}

static id find_info_scroll(id view, int depth) {
    if (!view || depth > 16) return 0;
    const char *name = class_getName(object_getClass(view));
    if (contains(name, "HostingScrollView")) {
        struct cg_rect frame = ((struct cg_rect (*)(id, SEL))objc_msgSend)(
            view, sel_registerName("frame"));
        if (frame.size.width > 300 && frame.size.height > 700 &&
            frame.size.height < 770) return view;
    }
    id children = ((id (*)(id, SEL))objc_msgSend)(view,
        sel_registerName("subviews"));
    NSUInteger count = children ? ((NSUInteger (*)(id, SEL))objc_msgSend)(
        children, sel_registerName("count")) : 0;
    for (NSUInteger i = 0; i < count; ++i) {
        id child = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            children, sel_registerName("objectAtIndex:"), i);
        id result = find_info_scroll(child, depth + 1);
        if (result) return result;
    }
    return 0;
}

static void hide_info_credits(id root) {
    if (info_overlay_added) return;
    id scroll = find_info_scroll(root, 0);
    if (!scroll) return;
    struct cg_rect frame = ((struct cg_rect (*)(id, SEL))objc_msgSend)(
        scroll, sel_registerName("frame"));
    struct cg_rect cover = {{0, 392}, {frame.size.width, 1800}};
    Class view_class = objc_getClass("UIView");
    id overlay = ((id (*)(id, SEL))objc_msgSend)(view_class,
        sel_registerName("alloc"));
    overlay = ((id (*)(id, SEL, struct cg_rect))objc_msgSend)(
        overlay, sel_registerName("initWithFrame:"), cover);
    Class color_class = objc_getClass("UIColor");
    id black = ((id (*)(id, SEL))objc_msgSend)(color_class,
        sel_registerName("blackColor"));
    ((void (*)(id, SEL, id))objc_msgSend)(overlay,
        sel_registerName("setBackgroundColor:"), black);
    ((void (*)(id, SEL, id))objc_msgSend)(scroll,
        sel_registerName("addSubview:"), overlay);
    info_overlay_added = 1;
    debug_line("credits-overlay", "added");
}

static void patched_did_appear(id self, SEL cmd, BOOL animated) {
    original_did_appear(self, cmd, animated);
    id tab = ((id (*)(id, SEL))objc_msgSend)(self,
        sel_registerName("tabBarController"));
    if (!tab && contains(class_getName(object_getClass(self)), "TabBarController"))
        tab = self;
    if (!tab) return;
    NSUInteger selected = ((NSUInteger (*)(id, SEL))objc_msgSend)(tab,
        sel_registerName("selectedIndex"));
    id tab_view = ((id (*)(id, SEL))objc_msgSend)(tab, sel_registerName("view"));
    if (selected == 0) {
        attach_bulk_button(tab_view);
        if (bulk_button) ((void (*)(id, SEL, BOOL))objc_msgSend)(bulk_button,
            sel_registerName("setHidden:"), 0);
        return;
    }
    if (bulk_button) ((void (*)(id, SEL, BOOL))objc_msgSend)(bulk_button,
        sel_registerName("setHidden:"), 1);
    if (selected != 2) return;
    id view = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("view"));
    hide_info_credits(view);
}

static void patched_arguments(id self, SEL cmd, id arguments) {
    if (!arguments) {
        original_arguments(self, cmd, arguments);
        return;
    }
    NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        arguments, sel_registerName("count"));
    int is_arpoison = 0;
    for (NSUInteger i = 0; i < count; ++i) {
        id item = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            arguments, sel_registerName("objectAtIndex:"), i);
        if (contains(utf8(item), "arpoison")) { is_arpoison = 1; break; }
    }
    char gateway_ip[32], gateway_mac[32];
    int has_gateway = is_arpoison && get_gateway(gateway_ip, sizeof(gateway_ip),
                                                gateway_mac, sizeof(gateway_mac));
    if (is_arpoison) debug_line("gateway-found", has_gateway ? "yes" : "no");
    char phone_mac[32] = {0};
    int has_phone_mac = is_arpoison && get_interface_mac("en0", phone_mac, sizeof(phone_mac));
    if (is_arpoison) debug_line("phone-mac", has_phone_mac ? phone_mac : "missing");
    if (is_arpoison && !repair_in_progress)
        memset(&pending_block, 0, sizeof(pending_block));
    Class array_class = objc_getClass("NSMutableArray");
    id result = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
        array_class, sel_registerName("arrayWithCapacity:"), count);
    for (NSUInteger i = 0; i < count; ++i) {
        id item = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            arguments, sel_registerName("objectAtIndex:"), i);
        if (is_arpoison && i > 0) {
            id previous = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                arguments, sel_registerName("objectAtIndex:"), i - 1);
            const char *flag = utf8(previous);
            if (equals(flag, "-s") && utf8(item))
                snprintf(pending_block.ip, sizeof(pending_block.ip), "%s", utf8(item));
            if (equals(flag, "-r") && utf8(item))
                snprintf(pending_block.real_mac, sizeof(pending_block.real_mac), "%s", utf8(item));
            if (has_gateway && (!utf8(item) || !utf8(item)[0])) {
                if (equals(flag, "-d")) item = string_from_utf8(gateway_ip);
                else if (equals(flag, "-t")) item = string_from_utf8(gateway_mac);
            }
            if (equals(flag, "-r") && has_phone_mac && !repair_in_progress)
                item = string_from_utf8(phone_mac);
        }
        ((void (*)(id, SEL, id))objc_msgSend)(
            result, sel_registerName("addObject:"), rewrite_argument(item));
    }
    original_arguments(self, cmd, result);
    if (capture_root_task) {
        id task_path = ((id (*)(id, SEL))objc_msgSend)(self,
            sel_registerName("launchPath"));
        if (contains(utf8(task_path), "/harpy-reloaded/aegis"))
            captured_root_task = self;
    }
    if (!is_arpoison) {
        id task_path = ((id (*)(id, SEL))objc_msgSend)(self,
            sel_registerName("launchPath"));
        debug_line("task-args-path", utf8(task_path));
        for (NSUInteger j = 0; j < count; ++j) {
            id arg = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(result,
                sel_registerName("objectAtIndex:"), j);
            debug_line("task-arg", utf8(arg));
        }
    }
    if (is_arpoison && !repair_in_progress && pending_block.ip[0]) {
        char arp_mac[32];
        if (get_mac_from_arp_table(pending_block.ip, arp_mac, sizeof(arp_mac)))
            snprintf(pending_block.real_mac, sizeof(pending_block.real_mac), "%s", arp_mac);
        debug_line("block-target", pending_block.ip);
        debug_line("block-real-mac", pending_block.real_mac);
    }
}

__attribute__((constructor)) static void install_paths(void) {
    Method exists = class_getInstanceMethod(objc_getClass("NSFileManager"),
        sel_registerName("fileExistsAtPath:"));
    Class task_class = objc_getClass("NSConcreteTask");
    if (!task_class) task_class = objc_getClass("NSTask");
    Method launch_path = class_getInstanceMethod(task_class,
        sel_registerName("setLaunchPath:"));
    Method arguments = class_getInstanceMethod(task_class,
        sel_registerName("setArguments:"));
    Method terminate = class_getInstanceMethod(task_class,
        sel_registerName("terminate"));
    Method interrupt = class_getInstanceMethod(task_class,
        sel_registerName("interrupt"));
    Method launch = class_getInstanceMethod(task_class,
        sel_registerName("launch"));
    Class commands = objc_getClass("_TtC13HarpyReloaded10MCCommands");
    Method running_ip = commands ? class_getClassMethod(commands,
        sel_registerName("runningBlocksForIpWithIp:")) : 0;
    Method running_arp = commands ? class_getClassMethod(commands,
        sel_registerName("runningBlocksForArp")) : 0;
    Method did_appear = class_getInstanceMethod(objc_getClass("UIViewController"),
        sel_registerName("viewDidAppear:"));
    Class scanner = objc_getClass("_TtC13HarpyReloaded10LanScanner");
    Method found_device = scanner ? class_getInstanceMethod(scanner,
        sel_registerName("lanScanDidFindNewDevice:")) : 0;
    if (exists) original_exists = (void *)method_setImplementation(exists, (IMP)patched_exists);
    if (launch_path) original_launch_path = (void *)method_setImplementation(launch_path, (IMP)patched_launch_path);
    if (arguments) original_arguments = (void *)method_setImplementation(arguments, (IMP)patched_arguments);
    if (terminate) original_terminate = (void *)method_setImplementation(terminate, (IMP)patched_terminate);
    if (interrupt) original_interrupt = (void *)method_setImplementation(interrupt, (IMP)patched_interrupt);
    if (launch) original_launch = (void *)method_setImplementation(launch, (IMP)patched_launch);
    if (running_ip) method_setImplementation(running_ip, (IMP)patched_running_ip);
    if (running_arp) method_setImplementation(running_arp, (IMP)patched_running_arp);
    if (did_appear) original_did_appear = (void *)method_setImplementation(did_appear, (IMP)patched_did_appear);
    if (found_device) {
        original_found_device = (void *)method_setImplementation(found_device,
            (IMP)patched_found_device);
        debug_line("scan-hook", "installed");
    } else debug_line("scan-hook", "unavailable");
    void (*hook_function)(void *, void *, void **) = (void *)dlsym((void *)-2,
        "MSHookFunction");
    const char *(*image_header)(unsigned) = (void *)dlsym((void *)-2,
        "_dyld_get_image_header");
    const char *(*image_name)(unsigned) = (void *)dlsym((void *)-2,
        "_dyld_get_image_name");
    unsigned (*image_count)(void) = (void *)dlsym((void *)-2,
        "_dyld_image_count");
    const char *app_header = 0;
    if (image_header && image_name && image_count) {
        for (unsigned i = 0; i < image_count(); ++i) {
            const char *name = image_name(i);
            if (contains(name, "/HarpyReloaded.app/HarpyReloaded")) {
                app_header = image_header(i);
                break;
            }
        }
    }
    if (hook_function && app_header) {
        swift_string_to_nsstring = (void *)(app_header + 0x1152fc);
        void *target = (void *)(app_header + 0x39610);
        hook_function(target, (void *)patched_swift_unblock,
            (void **)&original_swift_unblock);
        debug_line("swift-unblock-hook", "installed");
    } else {
        debug_line("swift-unblock-hook", "unavailable");
    }
}

