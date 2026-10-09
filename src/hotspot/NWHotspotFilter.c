// Bounded PF frontend. Does not load pf.conf, replace a ruleset, or flush states.
// Only NukeWireless-labelled rules and the selected hotspot client's states change.
#define PRIVATE 1
#include "vendor/pfvar.h"
#include <sys/ioctl.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <net/route.h>
#include <net/if_dl.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stddef.h>

#define OWNER "NukeWirelessHotspot:"
#define MAX_ADDRESSES 16
struct client_address { int family; unsigned char bytes[16]; };
static int fd = -1;
static int fail(const char *code) {
    printf("{\"ok\":false,\"error_code\":\"%s\",\"errno\":%d}\n", code, errno);
    if (fd >= 0) close(fd); return 1;
}
static int authorized(const char *executable) {
    if (getuid() == 0) return 1; // Explicit SSH root diagnostics.
    if (getuid() != 501 || geteuid() != 0) return 0;
    char self[PATH_MAX], parent[PATH_MAX], expected[PATH_MAX];
    // Same libproc signature already verified by the Bluetooth runner.
    int (*pidpath)(int, void *, uint32_t) = dlsym(RTLD_DEFAULT, "proc_pidpath");
    if (!pidpath || !realpath(executable, self) || pidpath(getppid(), parent, sizeof(parent)) <= 0) return 0;
    const char *suffix = "/usr/libexec/harpy-reloaded/nw-hotspot";
    size_t root = strlen(self), tail = strlen(suffix);
    if (root < tail || strcmp(self + root - tail, suffix)) return 0;
    root -= tail;
    if (snprintf(expected, sizeof(expected), "%.*s/Applications/HarpyReloaded.app/HarpyReloaded", (int)root, self) >= (int)sizeof(expected)) return 0;
    char resolved[PATH_MAX]; return realpath(expected, resolved) && !strcmp(parent, resolved);
}
static int parse_mac(const char *text, unsigned char bytes[6], char canonical[18]) {
    unsigned value[6]; int used = 0;
    if (sscanf(text, "%2x:%2x:%2x:%2x:%2x:%2x%n", &value[0], &value[1], &value[2], &value[3], &value[4], &value[5], &used) != 6 || text[used]) return 0;
    unsigned any = 0;
    for (int i = 0; i < 6; ++i) { bytes[i] = value[i]; any |= value[i]; }
    if (!any || (bytes[0] & 1)) return 0;
    snprintf(canonical, 18, "%02x%02x%02x%02x%02x%02x", value[0], value[1], value[2], value[3], value[4], value[5]); return 1;
}
static int bridge_for(struct in_addr target, char interface[IFNAMSIZ]) {
    struct ifaddrs *first = NULL; if (getifaddrs(&first)) return 0;
    int result = 0;
    for (struct ifaddrs *p = first; p; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
        struct in_addr local = ((struct sockaddr_in *)p->ifa_addr)->sin_addr;
        if (local.s_addr == target.s_addr) { result = -1; break; }
        if (!p->ifa_netmask || strncmp(p->ifa_name, "bridge", 6)) continue;
        uint32_t mask = ntohl(((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr), ip = ntohl(target.s_addr), host = ~mask;
        if (!mask || host < 3 || (host & (host + 1)) || (ip & mask) != (ntohl(local.s_addr) & mask) || !(ip & host) || (ip & host) == host) continue;
        strlcpy(interface, p->ifa_name, IFNAMSIZ); result = 1;
    }
    freeifaddrs(first); return result == 1;
}
// Kernel neighbour entries bind IPv4/IPv6 addresses to the selected link-layer
// identity. Never infer an IPv6 address from a MAC or block the entire subnet.
static int neighbours(int family, const char *interface, const unsigned char mac[6], struct client_address *addresses, int count, struct in_addr target, int *matched_v4) {
    int mib[] = {CTL_NET, PF_ROUTE, 0, family, NET_RT_FLAGS, RTF_LLINFO}; size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) || size > 4 * 1024 * 1024) return -1;
    char *buffer = malloc(size ? size : 1); if (!buffer) return -1;
    if (sysctl(mib, 6, buffer, &size, NULL, 0)) { free(buffer); return -1; }
    unsigned index = if_nametoindex(interface);
    for (size_t offset = 0; offset + sizeof(struct rt_msghdr) <= size;) {
        struct rt_msghdr *message = (void *)(buffer + offset);
        if (message->rtm_msglen < sizeof(*message) || offset + message->rtm_msglen > size) { free(buffer); errno = EINVAL; return -1; }
        const struct sockaddr *values[RTAX_MAX] = {0}; size_t cursor = sizeof(*message);
        for (int i = 0; i < RTAX_MAX; ++i) if (message->rtm_addrs & (1 << i)) {
            if (cursor + 2 > message->rtm_msglen) break;
            const struct sockaddr *sa = (void *)((char *)message + cursor);
            size_t advance = sa->sa_len ? ((sa->sa_len + sizeof(uint32_t)-1) & ~(sizeof(uint32_t)-1)) : sizeof(uint32_t);
            if (sa->sa_len < 2 || cursor + advance > message->rtm_msglen) break;
            values[i] = sa; cursor += advance;
        }
        const struct sockaddr_dl *link = (void *)values[RTAX_GATEWAY];
        const struct sockaddr *destination = values[RTAX_DST];
        if (message->rtm_index == index && link && link->sdl_family == AF_LINK && link->sdl_alen == 6 &&
            link->sdl_len >= offsetof(struct sockaddr_dl, sdl_data) + link->sdl_nlen + 6 &&
            !memcmp(LLADDR(link), mac, 6) && destination && destination->sa_family == family) {
            if (family == AF_INET && destination->sa_len >= sizeof(struct sockaddr_in)) {
                if (((const struct sockaddr_in *)destination)->sin_addr.s_addr == target.s_addr) *matched_v4 = 1;
            } else if (family == AF_INET6 && destination->sa_len >= sizeof(struct sockaddr_in6) && count < MAX_ADDRESSES) {
                const struct in6_addr *a = &((const struct sockaddr_in6 *)destination)->sin6_addr;
                if (!IN6_IS_ADDR_MULTICAST(a) && !IN6_IS_ADDR_UNSPECIFIED(a) && !IN6_IS_ADDR_LINKLOCAL(a)) {
                    int duplicate = 0;
                    for (int j = 0; j < count; ++j) if (addresses[j].family == AF_INET6 && !memcmp(addresses[j].bytes, a, 16)) duplicate = 1;
                    if (!duplicate) { addresses[count].family = AF_INET6; memcpy(addresses[count++].bytes, a, 16); }
                }
            }
        }
        offset += message->rtm_msglen;
    }
    free(buffer); return count;
}
static int rules_count(struct pfioc_rule *request) {
    memset(request, 0, sizeof(*request)); request->rule.action = PF_DROP;
    if (ioctl(fd, DIOCGETRULES, request) || request->nr > 4096) return -1;
    return (int)request->nr;
}
static int get_rule(struct pfioc_rule *request, unsigned index) {
    request->nr = index;
    if (ioctl(fd, DIOCGETRULE, request)) return 0;
    return memchr(request->rule.label, 0, sizeof(request->rule.label)) && memchr(request->rule.ifname, 0, IFNAMSIZ);
}
static int remove_rules(const char *prefix) {
    struct pfioc_rule request; int count = rules_count(&request); if (count < 0) return 0;
    for (int i = count - 1; i >= 0; --i) {
        if (!get_rule(&request, i)) return 0;
        if (strncmp(request.rule.label, prefix, strlen(prefix))) continue;
        struct pfioc_rule change = {0}; change.rule.action = PF_DROP; change.action = PF_CHANGE_GET_TICKET;
        if (ioctl(fd, DIOCCHANGERULE, &change)) return 0;
        change.action = PF_CHANGE_REMOVE; change.nr = i;
        if (ioctl(fd, DIOCCHANGERULE, &change)) return 0;
        // Rule removal changes the ruleset ticket; refresh before the next read.
        if (rules_count(&request) < 0) return 0;
    }
    return 1;
}
static void address_rule(struct pf_rule_addr *rule, const struct client_address *address) {
    rule->addr.type = PF_ADDR_ADDRMASK; size_t length = address->family == AF_INET ? 4 : 16;
    memcpy(&rule->addr.v.a.addr, address->bytes, length); memset(&rule->addr.v.a.mask, 0xff, length);
}
static int add_rule(const char *label, const char *interface, const struct client_address *address, int source) {
    struct pfioc_rule request = {0}; request.rule.action = PF_DROP; request.action = PF_CHANGE_GET_TICKET;
    if (ioctl(fd, DIOCCHANGERULE, &request)) return 0;
    request.action = PF_CHANGE_ADD_HEAD; request.rule.quick = 1; request.rule.af = address->family;
    request.rule.direction = PF_INOUT; request.rule.rtableid = (unsigned)-1;
    strlcpy(request.rule.ifname, interface, sizeof(request.rule.ifname)); strlcpy(request.rule.label, label, sizeof(request.rule.label));
    address_rule(source ? &request.rule.src : &request.rule.dst, address);
    return ioctl(fd, DIOCCHANGERULE, &request) == 0;
}
static int kill_client_states(const struct client_address *address) {
    for (int source = 0; source < 2; ++source) {
        struct pfioc_state_kill request = {0}; request.psk_af = address->family;
        struct pfioc_state_addr_kill *value = source ? &request.psk_src : &request.psk_dst;
        value->addr.type = PF_ADDR_ADDRMASK;
        size_t length = address->family == AF_INET ? 4 : 16;
        memcpy(&value->addr.v.a.addr, address->bytes, length); memset(&value->addr.v.a.mask, 0xff, length);
        if (ioctl(fd, DIOCKILLSTATES, &request)) return 0;
    }
    return 1;
}
static int status(void) {
    struct pf_status state = {0}; struct pfioc_rule request;
    if (ioctl(fd, DIOCGETSTATUS, &state)) return fail("pf_contract");
    int count = rules_count(&request); if (count < 0) return fail("pf_contract");
    // Validate all copyouts before emitting any partial JSON.
    for (int i = 0; i < count; ++i) if (!get_rule(&request, i)) return fail("pf_contract");
    printf("{\"ok\":true,\"enabled\":%s,\"rules\":[", state.running ? "true" : "false"); int written = 0;
    for (int i = 0; i < count; ++i) {
        if (!get_rule(&request, i)) { close(fd); return 1; }
        if (strncmp(request.rule.label, OWNER, strlen(OWNER))) continue;
        // Other privileged programs can also create labels. Escape every copyout.
        printf("%s\"", written++ ? "," : "");
        for (const unsigned char *p=(void *)request.rule.label; *p; ++p) {
            if (*p < 32 || *p == '\\' || *p == '"') printf("\\u%04x", *p); else putchar(*p);
        }
        putchar('"');
    }
    printf("]}\n"); close(fd); return 0;
}
int main(int argc, char **argv) {
    if (!authorized(argv[0])) { errno = EPERM; return fail("permissions"); }
    if (argc != 2 && argc != 4) { errno = EINVAL; return fail("arguments"); }
    if (strcmp(argv[1], "status") && strcmp(argv[1], "block") && strcmp(argv[1], "unblock")) { errno = EINVAL; return fail("arguments"); }
    if ((!strcmp(argv[1], "status")) != (argc == 2)) { errno = EINVAL; return fail("arguments"); }
    struct utsname os; if (uname(&os) || atoi(os.release) < 21 || atoi(os.release) > 24) return fail("unsupported");
    fd = open("/dev/pf", !strcmp(argv[1], "status") ? O_RDONLY : O_RDWR); if (fd < 0) return fail("pf_unavailable");
    if (argc == 2) return status();
    struct in_addr ip; unsigned char mac[6]; char canonical[18], prefix[64], interface[IFNAMSIZ];
    if (inet_pton(AF_INET, argv[2], &ip) != 1 || !parse_mac(argv[3], mac, canonical)) { errno = EINVAL; return fail("arguments"); }
    snprintf(prefix, sizeof(prefix), OWNER "%s:", canonical);
    if (!strcmp(argv[1], "unblock")) {
        if (!remove_rules(prefix)) return fail("pf_remove"); return status();
    }
    if (!bridge_for(ip, interface)) { errno = EADDRNOTAVAIL; return fail("hotspot_network"); }
    struct client_address addresses[MAX_ADDRESSES] = {{.family = AF_INET}}; memcpy(addresses[0].bytes, &ip, 4);
    int matched = 0, count = neighbours(AF_INET, interface, mac, addresses, 1, ip, &matched);
    if (count < 0 || !matched) { errno = EADDRNOTAVAIL; return fail("hotspot_identity"); }
    count = neighbours(AF_INET6, interface, mac, addresses, count, ip, &matched); if (count < 0) return fail("hotspot_neighbors");
    struct pf_status state = {0}; struct pfioc_rule probe;
    if (ioctl(fd, DIOCGETSTATUS, &state) || rules_count(&probe) < 0) return fail("pf_contract");
    if (!state.running && ioctl(fd, DIOCSTART) && errno != EEXIST) return fail("pf_enable");
    if (!remove_rules(prefix)) return fail("pf_remove");
    for (int i = 0; i < count; ++i) for (int source = 0; source < 2; ++source) {
        char label[64]; snprintf(label, sizeof(label), "%s%d:%d", prefix, i, source);
        if (!add_rule(label, interface, &addresses[i], source)) { int saved = errno; remove_rules(prefix); errno = saved; return fail("pf_apply"); }
    }
    for (int i = 0; i < count; ++i) if (!kill_client_states(&addresses[i])) {
        int saved = errno; remove_rules(prefix); errno = saved; return fail("pf_states");
    }
    // Read back instead of treating a launched helper as a completed block.
    return status();
}
