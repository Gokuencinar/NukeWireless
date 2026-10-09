// Execute the real rule operations against an in-memory ioctl substitute.
// Never opens /dev/pf or modifies the build host's firewall.
#define PRIVATE 1
#include "../src/hotspot/vendor/pfvar.h"
#include <sys/ioctl.h>
#include <stdarg.h>
#include <assert.h>
#include <string.h>
#include <errno.h>
static struct pf_rule fixture[64];
static unsigned fixture_count, ticket = 1, state_kills;
static int reject_add;
static int fixture_ioctl(int descriptor, unsigned long operation, ...);
#define ioctl fixture_ioctl
#define main hotspot_cli_main
#include "../src/hotspot/NWHotspotFilter.c"
#undef main
#undef ioctl
static int fixture_ioctl(int descriptor, unsigned long operation, ...) {
    (void)descriptor; va_list args; va_start(args, operation); void *value = va_arg(args, void *); va_end(args);
    struct pfioc_rule *rule = value;
    if (operation == DIOCGETSTATUS) { ((struct pf_status *)value)->running = 1; return 0; }
    if (operation == DIOCGETRULES) { rule->nr = fixture_count; rule->ticket = ticket; return 0; }
    if (operation == DIOCGETRULE) {
        assert(rule->ticket == ticket && rule->nr < fixture_count); rule->rule = fixture[rule->nr]; return 0;
    }
    if (operation == DIOCKILLSTATES) {
        struct pfioc_state_kill *state = value;
        assert(state->psk_af == AF_INET || state->psk_af == AF_INET6);
        assert(!memcmp(&state->psk_src.addr.v.a.mask, "\xff\xff\xff\xff", 4) ||
               !memcmp(&state->psk_dst.addr.v.a.mask, "\xff\xff\xff\xff", 4));
        ++state_kills; return 0;
    }
    assert(operation == DIOCCHANGERULE);
    if (rule->action == PF_CHANGE_GET_TICKET) { rule->ticket = ticket; return 0; }
    assert(rule->ticket == ticket);
    if (rule->action == PF_CHANGE_REMOVE) {
        assert(rule->nr < fixture_count);
        memmove(&fixture[rule->nr], &fixture[rule->nr + 1], (--fixture_count - rule->nr) * sizeof(*fixture));
    } else {
        assert(rule->action == PF_CHANGE_ADD_HEAD);
        if (reject_add) { errno = EIO; return -1; }
        memmove(&fixture[1], &fixture[0], fixture_count++ * sizeof(*fixture)); fixture[0] = rule->rule;
    }
    ++ticket; return 0;
}
int main(void) {
    unsigned char mac[6]; char canonical[18];
    assert(parse_mac("02:11:22:33:44:55", mac, canonical) && !strcmp(canonical, "021122334455"));
    assert(!parse_mac("01:11:22:33:44:55", mac, canonical));
    assert(!parse_mac("00:00:00:00:00:00", mac, canonical));
    assert(!parse_mac("02:11:22:33:44:55:66", mac, canonical));
    strcpy(fixture[fixture_count++].label, "system-hotspot-NAT");
    strcpy(fixture[fixture_count++].label, OWNER "021122334466:0:0");
    const char *own = OWNER "021122334455:";
    struct client_address address = {.family = AF_INET};
    assert(inet_pton(AF_INET, "172.20.10.2", address.bytes) == 1);
    assert(add_rule(OWNER "021122334455:0:0", "bridge100", &address, 0));
    assert(add_rule(OWNER "021122334455:0:1", "bridge100", &address, 1));
    assert(fixture_count == 4 && fixture[0].quick && fixture[0].action == PF_DROP);
    assert(!strcmp(fixture[0].ifname, "bridge100"));
    assert(!memcmp(&fixture[0].src.addr.v.a.addr, address.bytes, 4));
    assert(!memcmp(&fixture[1].dst.addr.v.a.addr, address.bytes, 4));
    assert(kill_client_states(&address) && state_kills == 2);
    assert(remove_rules(own) && fixture_count == 2);
    assert(!strcmp(fixture[0].label, "system-hotspot-NAT"));
    assert(!strcmp(fixture[1].label, OWNER "021122334466:0:0"));
    assert(remove_rules(own) && fixture_count == 2); // idempotent unblock
    reject_add = 1; assert(!add_rule(OWNER "021122334455:0:0", "bridge100", &address, 0));
    assert(fixture_count == 2); // failure preserves unrelated rules
    puts("Hotspot filter: ownership, host masks, state selection and failure checks passed"); return 0;
}
