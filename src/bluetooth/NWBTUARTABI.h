#ifndef NW_BT_UART_ABI_H
#define NW_BT_UART_ABI_H
#include <stdint.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <termios.h>

// iPhoneOS SDK omits these headers; declarations checked against Apple XNU
// xnu-8792.61.2 bsd/sys/{kern_control,sys_domain,ttycom}.h. Prefer SDK definitions
// where available and assert the same layout on both macOS tests and iOS builds.
#if __has_include(<sys/kern_control.h>)
#include <sys/kern_control.h>
#else
struct ctl_info { uint32_t ctl_id; char ctl_name[96]; };
struct sockaddr_ctl {
    uint8_t sc_len, sc_family;
    uint16_t ss_sysaddr;
    uint32_t sc_id, sc_unit, sc_reserved[5];
};
#define CTLIOCGINFO _IOWR('N', 3, struct ctl_info)
#endif
#if __has_include(<sys/sys_domain.h>)
#include <sys/sys_domain.h>
#else
#define SYSPROTO_CONTROL 2
#define AF_SYS_CONTROL 2
#endif
#if __has_include(<sys/ttycom.h>)
#include <sys/ttycom.h>
#else
#define TIOCGETA _IOR('t', 19, struct termios)
#define TIOCSETA _IOW('t', 20, struct termios)
#endif
_Static_assert(sizeof(struct ctl_info) == 100, "XNU control info layout");
_Static_assert(sizeof(struct sockaddr_ctl) == 32, "XNU kernel control address layout");
_Static_assert(offsetof(struct sockaddr_ctl, sc_id) == 4, "XNU control ID offset");
_Static_assert(sizeof(struct termios) == 72, "64-bit Darwin termios layout");
#endif
