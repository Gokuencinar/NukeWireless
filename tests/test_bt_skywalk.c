#include "../src/bluetooth/NWBTSkywalkABI.h"
#include "../src/bluetooth/NWBTService.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (unsigned ios = 0; ios < 22; ++ios)
        for (unsigned darwin = 0; darwin < 30; ++darwin)
            assert(NWBTSkywalkOSAllowed(ios, darwin) ==
                   (ios >= 15 && ios <= 18 && darwin == ios + 6));
    uint8_t commands[64] = {0};
    assert(!NWBTExtendedAdvertisingCommands(commands, sizeof commands));
    const unsigned required[] = {289, 290, 291, 293, 295, 296};
    for (size_t i = 0; i < sizeof required / sizeof *required; ++i)
        commands[required[i] / 8] |= (uint8_t)(1u << (required[i] % 8));
    assert(NWBTExtendedAdvertisingCommands(commands, sizeof commands));
    for (size_t i = 0; i < sizeof required / sizeof *required; ++i) {
        commands[required[i] / 8] ^= (uint8_t)(1u << (required[i] % 8));
        assert(!NWBTExtendedAdvertisingCommands(commands, sizeof commands));
        commands[required[i] / 8] ^= (uint8_t)(1u << (required[i] % 8));
    }
    assert(!NWBTExtendedAdvertisingCommands(NULL, 64));
    assert(!NWBTExtendedAdvertisingCommands(commands, 63));
    assert(!NWBTExtendedAdvertisingCommands(commands, 65));
    assert(NWBTServiceDomainIndex("user/501") == 0);
    assert(NWBTServiceDomainIndex("system") == 1);
    const char *bad[] = {NULL, "", "user/0", "user/502", "system/other", "system; reboot", "../system"};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; ++i) assert(NWBTServiceDomainIndex(bad[i]) == -1);
    assert(!NWBTServiceDomain(2) && !NWBTServiceLabel(2));
    assert(!strcmp(NWBTServiceLabel(0), "user/501/com.apple.bluetoothd"));
    assert(!strcmp(NWBTServiceLabel(1), "system/com.apple.bluetoothd"));
    // Only a complete, unambiguous live PID snapshot can preserve a UART job.
    assert(NWBTServicePID("system/com.apple.bluetoothd = {\n\tpid = 123\n}") == 123);
    const char *badPID[] = {NULL, "", "\n\tpid = 1\n", "\n\tpid = 0\n", "\n\tpid = -2\n",
        "\n\tpid = 12", "\n\tpid = 12x\n", "\n\tpid = 2147483648\n",
        "\n\tpid = 12\n\tpid = 13\n", "\n\tpid = \n"};
    for (size_t i = 0; i < sizeof badPID / sizeof *badPID; ++i) assert(!NWBTServicePID(badPID[i]));
    assert(NWBTRecoveryDecision('u', 1, 'p') == NWBTRecoveryObserve);
    // EOF, unknown completion and cleanup failure must recover, never preserve.
    assert(NWBTRecoveryDecision('u', 0, 'p') == NWBTRecoveryRetireAndRestore);
    assert(NWBTRecoveryDecision('u', -1, 'p') == NWBTRecoveryRetireAndRestore);
    assert(NWBTRecoveryDecision('u', 1, 'r') == NWBTRecoveryRetireAndRestore);
    assert(NWBTRecoveryDecision('u', 1, 'x') == NWBTRecoveryRetireAndRestore);
    assert(NWBTRecoveryDecision('a', 1, 'p') == NWBTRecoveryRestore);
    assert(NWBTRecoveryDecision('a', 0, 0) == NWBTRecoveryRestore);
    assert(NWBTRecoveryDecision(0, 0, 0) == NWBTRecoveryNone);
    assert(NWBTRecoveryDecision('x', 1, 'r') == NWBTRecoveryNone);
    puts("Skywalk admission, controller capabilities and recovery domains passed");
    return 0;
}
