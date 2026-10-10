#!/bin/sh
# Repair only the malformed NukeWireless directory record. Never remove files
# from the bootstrap or invoke dpkg removal. Close package managers first.
set -eu
package=com.gokuencinar.nukewireless
if [ "$(id -u)" != 0 ]; then
    echo 'Run this script as root.' >&2
    exit 1
fi
if [ "$#" -gt 1 ]; then
    echo 'Usage: sh repair_rootless_package_list.sh [dpkg-admindir]' >&2
    exit 1
fi
if [ "$#" = 1 ]; then
    admindir=$1
elif [ -f /var/jb/var/lib/dpkg/status ]; then
    admindir=/var/jb/var/lib/dpkg
else
    echo 'Rootless dpkg database not found; no changes made.' >&2
    exit 1
fi
[ -f "$admindir/status" ] && [ -d "$admindir/info" ] || exit 1
version=$(dpkg-query --admindir="$admindir" -W -f='${Version}' "$package")
case "$version" in
    '2.0.0~diagnostic5+bundle1'|'2.0.0~diagnostic6+bundle1'|'2.0.0~diagnostic6+bundle2') ;;
    *) echo "Unexpected package version: $version. No changes made." >&2; exit 1 ;;
esac
record=
for candidate in "$admindir/info/$package.list" "$admindir/info/$package:iphoneos-arm64.list"; do
    if [ -f "$candidate" ]; then
        if [ -n "$record" ] || [ -L "$candidate" ]; then
            echo 'Ambiguous or symbolic package record; no changes made.' >&2
            exit 1
        fi
        record=$candidate
    fi
done
[ -n "$record" ] || { echo 'Package file list not found.' >&2; exit 1; }
if ! grep -Fx '/var/jb/.' "$record" >/dev/null; then
    echo 'The malformed entry is absent; no changes needed.'
    exit 0
fi
backup=$(mktemp "$record.nw-backup.XXXXXX")
cp -p "$record" "$backup"
temporary=$(mktemp "$record.nw-repair.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
cp -p "$record" "$temporary"
# Use shell builtins: awk is not necessarily installed in a Dopamine bootstrap.
# Preserve every other byte, including a final line without a newline.
while :; do
    last_line=false
    IFS= read -r entry || last_line=true
    if [ "$entry" != '/var/jb/.' ]; then
        printf '%s' "$entry"
        if [ "$last_line" = false ]; then printf '\n'; fi
    fi
    if [ "$last_line" = true ]; then break; fi
done < "$backup" > "$temporary"
# Preserve permissions/ownership via cp -p, then replace on the same filesystem.
mv -f "$temporary" "$record"
trap - EXIT HUP INT TERM
echo "Removed only the /var/jb/. record. Backup: $backup"
echo 'You can now retry removing NukeWireless in your package manager.'
