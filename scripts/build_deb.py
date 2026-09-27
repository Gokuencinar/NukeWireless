"""Build a RootHide Harpy test package with runtime path repair.

The original package scripts are only read as inert archive data.
"""

from __future__ import annotations

import hashlib
import io
from pathlib import Path
import plistlib
import tarfile

from package_utils import (
    SOURCE, get_tar_member, pack_ar, read_ar, regular, symlink, tar_bytes,
)

HERE = Path(__file__).resolve().parents[1] / "build"
OUTPUT = HERE.parent / "dist" / "xyz.cypwn.harpy-reloaded_1.0.26+rh26_iphoneos-arm64e.deb"

ENTITLEMENTS = b'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.storage.AppBundles</key><true/>
<key>com.apple.private.security.storage.AppDataContainers</key><true/>
<key>com.apple.developer.networking.wifi-info</key><true/>
</dict></plist>
'''

POSTINST = b'''#!/bin/sh
set -e
ENT=/usr/share/harpy-reloaded-roothide/roothide.entitlements
APP=/Applications/HarpyReloaded.app/HarpyReloaded
BASE=/usr/libexec/harpy-reloaded
for executable in "$APP" "$BASE/aegis" "$BASE/arp-scan" "$BASE/arpspoof"; do
    ldid -Hsha256 -M "-S$ENT" "$executable"
done
ldid -S /usr/lib/TweakInject/HarpyRootHidePaths.dylib
chown root:wheel "$BASE/aegis"
chmod 6755 "$BASE/aegis"
if command -v uicache >/dev/null 2>&1; then
    uicache -p /Applications/HarpyReloaded.app || true
fi
exit 0
'''

FILTER = b'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Filter</key><dict><key>Bundles</key><array><string>me.midnightchips.harpy-reloaded</string></array></dict></dict></plist>
'''


def main() -> None:
    tweak_binary = (HERE.parent / "prebuilt" / "HarpyRootHidePaths_ios.dylib").read_bytes()
    if b"HarpyRootHide 1.0.26" not in tweak_binary:
        raise ValueError("prebuilt tweak is not the compiled 1.0.26 source")
    parts = read_ar(SOURCE.read_bytes())
    old_control = None
    with tarfile.open(fileobj=io.BytesIO(get_tar_member(parts, "control.tar")), mode="r:*") as tf:
        for item in tf:
            if item.name.lstrip("./") == "control":
                old_control = tf.extractfile(item).read().decode("utf-8", "replace")
                break
    if not old_control or "Package: xyz.cypwn.harpy-reloaded" not in old_control:
        raise ValueError("unexpected package")
    fields = []
    for line in old_control.replace("\r", "").splitlines():
        if line.startswith(("Version:", "Architecture:", "Pre-Depends:", "Depends:", "Description:", "Installed-Size:", "Maintainer:", "Depiction:", "SileoDepiction:", "Icon:")):
            continue
        if line:
            fields.append(line)
    fields += [
        "Maintainer: Local RootHide test build",
        "Version: 1.0.26+rh26",
        "Architecture: iphoneos-arm64e",
        "Pre-Depends: rootless-compat (>= 0.9)",
        "Depends: firmware (>= 16.0), ldid, arpoison, network-cmds, ellekit",
        "Description: Harpy Reloaded RootHide path repair test for iOS 16",
    ]
    control = ("\n".join(fields) + "\n").encode()
    control_entries = [regular("control", control), regular("postinst", POSTINST, 0o755)]

    entries: list[tuple[tarfile.TarInfo, bytes | None]] = []
    kept = set()
    with tarfile.open(fileobj=io.BytesIO(get_tar_member(parts, "data.tar")), mode="r:*") as tf:
        for old in tf:
            name = old.name.lstrip("./")
            if not name or name in ("var", "var/jb"):
                continue
            if name.startswith("var/jb/"):
                name = name[len("var/jb/"):]
            elif name not in ("Applications", "usr") and not name.startswith(("Applications/", "usr/")):
                raise ValueError(f"unexpected path: {name}")
            if (name.startswith("usr/share/harpy-reloaded-roothide/") or
                name == "usr/share/harpy-reloaded-roothide" or
                name.startswith("usr/lib/TweakInject/HarpyRootHidePaths.") or
                name.endswith(".roothidepatch")):
                continue
            if name in kept:
                raise ValueError(f"duplicate entry: {name}")
            kept.add(name)
            info = tarfile.TarInfo("./" + name)
            info.type = old.type
            info.mode = old.mode
            info.linkname = old.linkname
            info.mtime = 0
            if old.isfile():
                data = tf.extractfile(old).read()
                if name == "usr/libexec/harpy-reloaded/aegis" and old.name.lstrip("./").startswith("var/jb/"):
                    data = (HERE / "aegis_roothide_patched").read_bytes()
                elif name == "Applications/HarpyReloaded.app/Info.plist":
                    info_plist = plistlib.loads(data)
                    info_plist["CFBundleShortVersionString"] = "1.0.26"
                    info_plist["CFBundleVersion"] = "26"
                    data = plistlib.dumps(info_plist, fmt=plistlib.FMT_BINARY)
                elif name == "Applications/HarpyReloaded.app/HarpyReloaded":
                    old = b"http://standards-oui.ieee.org/oui/oui.txt\0"
                    new = b"https://standards-oui.ieee.org/oui/oui.txt\0"
                    if data.count(old) == 1:
                        offset = data.index(old)
                        if data[offset + len(old):offset + len(new)] != b"\0":
                            raise ValueError("no padding after IEEE vendor URL")
                        patched = bytearray(data)
                        patched[offset:offset + len(new)] = new
                        data = bytes(patched)
                    elif data.count(new) != 1:
                        raise ValueError("unexpected IEEE vendor URL in source app")
                info.size = len(data)
            else:
                data = None
            entries.append((info, data))

    for directory in ("usr/share", "usr/share/harpy-reloaded-roothide", "usr/lib/TweakInject"):
        if directory not in kept:
            info = tarfile.TarInfo("./" + directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            entries.append((info, None))
    entries += [
        regular("usr/share/harpy-reloaded-roothide/roothide.entitlements", ENTITLEMENTS),
        regular("usr/share/harpy-reloaded-roothide/oui_vendors.plist", (HERE / "oui_vendors.plist").read_bytes()),
        regular("usr/lib/TweakInject/HarpyRootHidePaths.dylib", tweak_binary, 0o755),
        regular("usr/lib/TweakInject/HarpyRootHidePaths.plist", FILTER),
        regular("Applications/HarpyReloaded.app/CreditsAvatar.jpg", (HERE.parent / "assets" / "CreditsAvatar.jpg").read_bytes()),
    ]
    for executable in (
        "Applications/HarpyReloaded.app/HarpyReloaded",
        "usr/libexec/harpy-reloaded/aegis",
        "usr/libexec/harpy-reloaded/arp-scan",
        "usr/libexec/harpy-reloaded/arpspoof",
        "usr/lib/TweakInject/HarpyRootHidePaths.dylib",
    ):
        if executable not in kept and executable != "usr/lib/TweakInject/HarpyRootHidePaths.dylib":
            raise ValueError(f"missing executable: {executable}")
        entries.append(symlink(executable + ".roothidepatch", "/usr/lib/DynamicPatches/AutoPatches.dylib"))

    output = pack_ar([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", tar_bytes(control_entries)),
        ("data.tar.gz", tar_bytes(entries)),
    ])
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(output)
    print(OUTPUT)
    print("sha256", hashlib.sha256(output).hexdigest())
    print("bytes", len(output))


if __name__ == "__main__":
    main()

