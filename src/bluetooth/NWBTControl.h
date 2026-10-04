#ifndef NWBT_CONTROL_H
#define NWBT_CONTROL_H
#include <stdatomic.h>
#include <stdbool.h>
#include <pthread.h>
#include <poll.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

// A private inherited socket carries cancellation, never a target PID or HCI data.
// The reader also treats app exit (EOF) as cancellation. Only admitted diagnostic
// callers start this monitor; normal CLI stdin and recovery are left alone.
typedef struct {
    int descriptor;
    pthread_t thread;
    bool started;
    atomic_bool finished, requested;
    void (*cancel)(void);
} NWBTCancellationMonitor;

static inline void *NWBTControlRead(void *context) {
    NWBTCancellationMonitor *monitor = context;
    while (!atomic_load(&monitor->finished)) {
        struct pollfd item = {monitor->descriptor, POLLIN, 0};
        int ready = poll(&item, 1, 100);
        if (ready < 0 && errno == EINTR) continue;
        if (!ready) continue;
        if (ready > 0 && (item.revents & (POLLIN | POLLHUP))) {
            char byte;
            ssize_t count = read(monitor->descriptor, &byte, 1);
            if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        }
        if (!atomic_load(&monitor->finished)) {
            atomic_store(&monitor->requested, true);
            monitor->cancel();
        }
        break;
    }
    close(monitor->descriptor);
    return NULL;
}

// 1: monitor started, 0: ordinary non-socket stdin, -1: setup failed.
static inline int NWBTStartCancellationMonitor(NWBTCancellationMonitor *monitor, int descriptor, void (*cancel)(void)) {
    monitor->started = false;
    atomic_init(&monitor->finished, false); atomic_init(&monitor->requested, false);
    struct stat info;
    if (fstat(descriptor, &info)) return -1;
    if (!S_ISSOCK(info.st_mode)) return 0;
    int copy = dup(descriptor);
    if (copy < 0) return -1;
    if (fcntl(copy, F_SETFD, FD_CLOEXEC) || fcntl(copy, F_SETFL, O_NONBLOCK)) { close(copy); return -1; }
    monitor->descriptor = copy; monitor->cancel = cancel;
    if (pthread_create(&monitor->thread, NULL, NWBTControlRead, monitor)) { close(copy); return -1; }
    monitor->started = true;
    return 1;
}

static inline void NWBTStopCancellationMonitor(NWBTCancellationMonitor *monitor) {
    atomic_store(&monitor->finished, true);
    if (monitor->started) { pthread_join(monitor->thread, NULL); monitor->started = false; }
}
#endif
