"""Build the Nuke Wireless RootHide package with runtime path repair.

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
OUTPUT = HERE.parent / "dist" / "com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb"

ENTITLEMENTS = b'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.storage.AppBundles</key><true/>
<key>com.apple.private.security.storage.AppDataContainers</key><true/>
</dict></plist>
'''

POSTINST = b'''#!/bin/sh
set -e
ENT=/usr/share/nukewireless-roothide/roothide.entitlements
APP=/Applications/HarpyReloaded.app/HarpyReloaded
BASE=/usr/libexec/harpy-reloaded
for executable in "$APP" "$BASE/aegis" "$BASE/arp-scan" "$BASE/arpspoof"; do
    ldid -Hsha256 -M "-S$ENT" "$executable"
done
ldid -S /usr/lib/TweakInject/NukeWirelessPaths.dylib
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
        if line.startswith(("Package:", "Version:", "Architecture:", "Pre-Depends:", "Depends:", "Conflicts:", "Replaces:", "Description:", "Installed-Size:", "Maintainer:", "Author:", "Name:", "Depiction:", "SileoDepiction:", "Icon:")):
            continue
        if line:
            fields.append(line)
    fields += [
        "Package: com.gokuencinar.nukewireless",
        "Maintainer: Gokuencinar",
        "Version: 1.0.25+rh25",
        "Architecture: iphoneos-arm64e",
        "Pre-Depends: rootless-compat (>= 0.9)",
        "Depends: firmware (>= 16.0), ldid, arpoison, network-cmds, ellekit",
        "Conflicts: xyz.cypwn.harpy-reloaded",
        "Replaces: xyz.cypwn.harpy-reloaded",
        "Description: Nuke Wireless Wi-Fi tools for iOS 16 (RootHide)",
        "Author: Gokuencinar",
        "Name: Nuke Wireless",
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
                if name == "usr/libexec/harpy-reloaded/aegis":
                    data = (HERE / "aegis_roothide_patched").read_bytes()
                elif name == "Applications/HarpyReloaded.app/Info.plist":
                    info_plist = plistlib.loads(data)
                    info_plist["CFBundleShortVersionString"] = "1.0.25"
                    info_plist["CFBundleVersion"] = "25"
                    info_plist["CFBundleDisplayName"] = "Nuke Wireless"
                    info_plist["CFBundleName"] = "Nuke Wireless"
                    info_plist["NSLocalNetworkUsageDescription"] = "Nuke Wireless busca equipos en tu red Wi-Fi local."
                    info_plist["CFBundleIconFiles"] = ["NukeWirelessIcon"]
                    info_plist["CFBundleIcons"] = {
                        "CFBundlePrimaryIcon": {
                            "CFBundleIconFiles": ["NukeWirelessIcon"],
                        }
                    }
                    data = plistlib.dumps(info_plist, fmt=plistlib.FMT_BINARY)
                elif name == "Applications/HarpyReloaded.app/HarpyReloaded":
                    old = b"http://standards-oui.ieee.org/oui/oui.txt"
                    new = b"https://standards-oui.ieee.org/oui/oui.txt"
                    if data.count(old) == 1:
                        offset = data.index(old)
                        if data[offset + len(old)] == 0:
                            old += b"\0"
                            new += b"\0"
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

    for directory in ("usr/share", "usr/share/nukewireless-roothide", "usr/lib/TweakInject"):
        if directory not in kept:
            info = tarfile.TarInfo("./" + directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            entries.append((info, None))
    entries += [
        regular("usr/share/nukewireless-roothide/roothide.entitlements", ENTITLEMENTS),
        regular("usr/share/nukewireless-roothide/oui_vendors.plist", (HERE / "oui_vendors.plist").read_bytes()),
        regular("usr/lib/TweakInject/NukeWirelessPaths.dylib", (HERE.parent / "prebuilt" / "NukeWirelessPaths_ios.dylib").read_bytes(), 0o755),
        regular("usr/lib/TweakInject/NukeWirelessPaths.plist", FILTER),
    ]
    app_root = "Applications/HarpyReloaded.app/"
    entries += [
        regular(app_root + "NukeWirelessIcon.png", (HERE.parent / "assets" / "NukeWirelessIcon.png").read_bytes()),
        regular(app_root + "CreditsAvatar.jpg", (HERE.parent / "assets" / "CreditsAvatar.jpg" ).read_bytes()),
    ]
    for executable in (
        "Applications/HarpyReloaded.app/HarpyReloaded",
        "usr/libexec/harpy-reloaded/aegis",
        "usr/libexec/harpy-reloaded/arp-scan",
        "usr/libexec/harpy-reloaded/arpspoof",
        "usr/lib/TweakInject/NukeWirelessPaths.dylib",
    ):
        if executable not in kept and executable != "usr/lib/TweakInject/NukeWirelessPaths.dylib":
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


