#include "../src/bluetooth/NWBTControl.h"
#include <sys/socket.h>
#include <assert.h>
#include <stdio.h>

static atomic_uint cancellations;
static void cancelled(void) { atomic_fetch_add(&cancellations, 1); }
static void awaitCancellation(void) {
    for (unsigned attempt = 0; attempt < 200 && !atomic_load(&cancellations); ++attempt) usleep(10000);
    assert(atomic_load(&cancellations) == 1);
}
int main(void) {
    atomic_init(&cancellations, 0);
    NWBTCancellationMonitor monitor;
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    // A request already queued before the privileged worker starts is retained.
    assert(write(pair[1], "ss", 2) == 2);
    assert(NWBTStartCancellationMonitor(&monitor, pair[0], cancelled) == 1);
    close(pair[0]); // Reader owns its private duplicate.
    awaitCancellation(); NWBTStopCancellationMonitor(&monitor);
    assert(atomic_load(&monitor.requested) && atomic_load(&monitor.requested_at_ns)); close(pair[1]);

    atomic_store(&cancellations, 0);
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    assert(NWBTStartCancellationMonitor(&monitor, pair[0], cancelled) == 1);
    close(pair[1]); // App death/EOF cancels without a signal from UID 501.
    awaitCancellation(); NWBTStopCancellationMonitor(&monitor);
    assert(atomic_load(&monitor.requested)); close(pair[0]);

    atomic_store(&cancellations, 0);
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    assert(NWBTStartCancellationMonitor(&monitor, pair[0], cancelled) == 1);
    NWBTStopCancellationMonitor(&monitor); close(pair[0]); close(pair[1]);
    assert(!atomic_load(&cancellations) && !atomic_load(&monitor.requested));

    int null = open("/dev/null", O_RDONLY);
    assert(null >= 0);
    assert(NWBTStartCancellationMonitor(&monitor, null, cancelled) == 0);
    NWBTStopCancellationMonitor(&monitor); close(null);
    assert(NWBTStartCancellationMonitor(&monitor, -1, cancelled) == -1);
    NWBTStopCancellationMonitor(&monitor);
    puts("PASS: queued stop, one-shot request, app EOF, normal completion and CLI isolation");
    return 0;
}
