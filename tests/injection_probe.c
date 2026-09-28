// Temporary diagnostic: confirms ElleKit loads matching TweakInject entries.
#include <fcntl.h>
#include <unistd.h>
__attribute__((constructor)) static void probe(void) {
    int fd = open("/var/mobile/Library/Caches/NukeWireless-probe.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { (void)write(fd, "probe loaded\n", 13); (void)close(fd); }
}
