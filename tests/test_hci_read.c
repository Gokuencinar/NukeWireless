#include "../src/bluetooth/NWBTHCIRead.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    uint8_t credits = 0, status = 0;
    uint8_t reply[70] = {0x0e, 68, 1, 2, 0x10, 0};
    assert(NWBTMatchReadReply(reply, 70, 0x1002, &credits, &status) == 1);
    assert(credits == 1 && status == 0);
    assert(NWBTMatchReadReply(reply, 69, 0x1002, &credits, &status) == -1);
    reply[1] = 67;
    assert(NWBTMatchReadReply(reply, 69, 0x1002, &credits, &status) == -1);
    reply[1] = 68;
    assert(NWBTMatchReadReply(reply, 70, 0x2003, &credits, &status) == 0);
    uint8_t rejected[] = {0x0e, 4, 1, 3, 0x20, 1};
    assert(NWBTMatchReadReply(rejected, sizeof rejected, 0x2003, &credits, &status) == 1 && status == 1);
    uint8_t commandStatus[] = {0x0f, 4, 0, 0, 3, 0x20};
    assert(NWBTMatchReadReply(commandStatus, 6, 0x2003, &credits, &status) == 0 && credits == 0);
    commandStatus[2] = 0x0c;
    assert(NWBTMatchReadReply(commandStatus, 6, 0x2003, &credits, &status) == 2 && status == 0x0c);
    assert(NWBTMatchReadReply(commandStatus, 6, 0x1001, &credits, &status) == 0);
    assert(NWBTReadReplySize(0x2008) == 0 && NWBTReadReplySize(0xfc00) == 0);
    assert(NWBTMatchReadReply(NULL, 0, 0x1001, &credits, &status) == -1);
    puts("PASS: bounded HCI read replies, opcode correlation, status and allowlist");
}
