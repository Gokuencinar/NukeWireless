#!/bin/sh
# Rootless/Dopamine support snapshot. No HCI connection or radio command.
# Run: sh collect_bt_transport_readonly.sh > bluetooth-transport.txt 2>&1
# No root password, extra package, or Bluetooth state change is required.
PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

printf 'NukeWireless Bluetooth transport snapshot v1\n'
if command -v uname >/dev/null 2>&1; then uname -m; fi
if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.machine kern.osrelease
fi
if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W '-f=${Package} ${Version}\n' \
        com.gokuencinar.nukewireless com.gokuencinar.nukewireless.bluetooth
fi

printf '\nUART registration (presence is not functional compatibility):\n'
if command -v sysctl >/dev/null 2>&1 && command -v strings >/dev/null 2>&1 &&
        command -v grep >/dev/null 2>&1; then
    # Apple XNU exposes this as CTLFLAG_RD. Print only the known BT control
    # name, never the complete registry of other installed kernel controls.
    if sysctl -b net.systm.kctl.reg_list | strings | grep -x 'com.apple.uart.bluetooth'; then
        printf 'uart_control_name_observed=yes\n'
    else
        printf 'uart_control_name_observed=unknown (not observed or read failed)\n'
    fi
else
    printf 'uart_control_name_observed=unknown (optional tools unavailable)\n'
fi
if [ -e /dev/btwake ]; then
    printf 'btwake_path_present=yes (not opened)\n'
else
    printf 'btwake_path_present=no\n'
fi

printf '\nInstalled Bluetooth component, read-only diagnostics:\n'
if [ -x /var/jb/usr/bin/nwbt-run ]; then
    /var/jb/usr/bin/nwbt-run --diagnostics
    printf '\nworker_diagnostics_exit=%s\n' "$?"
else
    printf 'worker_diagnostics=unavailable at rootless path\n'
fi
printf '\nSnapshot complete. No advertising test was requested.\n'
