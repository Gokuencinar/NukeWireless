// Temporary diagnostic: confirms ElleKit loads matching TweakInject entries.
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <dlfcn.h>
__attribute__((constructor)) static void probe(void) {
    syslog(LOG_NOTICE, "NukeWireless probe constructor reached");
    const char *home = getenv("HOME");
    char path[1024];
    if (!home) return;
    int length = snprintf(path, sizeof(path), "%s/Library/Caches/NukeWireless-probe.log", home);
    if (length < 0 || (size_t)length >= sizeof(path)) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { (void)write(fd, "probe loaded\n", 13); (void)close(fd); }
    void *library = dlopen("/usr/lib/TweakInject/NukeWirelessInfo.dylib", RTLD_NOW);
    syslog(LOG_NOTICE, "NukeWireless info dlopen: %s", library ? "loaded" : dlerror());
}
