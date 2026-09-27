"""Add only an Info extension to the known-working Nuke Wireless 1.0.25 package.

The source archive and its maintainer scripts are read as data, never executed.
Existing app and tweak binaries are copied unchanged.
"""

from __future__ import annotations

import copy
import hashlib
import io
import os
from pathlib import Path
import sys
import tarfile

try:
    import zstandard as zstd
except ImportError as exc:
    raise SystemExit("Install zstandard 0.25.0 before packaging") from exc

if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_nuke_info_deb.py <Nuke-Wireless-1.0.25.deb>")

source = Path(sys.argv[1]).resolve()
os.environ.setdefault("HARPY_SOURCE_DEB", str(source))
from package_utils import get_tar_member, pack_ar, read_ar, regular, symlink, tar_bytes  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "dist" / "com.gokuencinar.nukewireless_1.0.25+rh25.1_iphoneos-arm64e.deb"
EXPECTED_SOURCE_SHA256 = "f4b5282bf8aec2eef2a35f84f644aa3bb6e4a16230b7c7cd2789fea6da65cdbc"
INFO_LIBRARY = "usr/lib/TweakInject/NukeWirelessInfo.dylib"
INFO_FILTER = "usr/lib/TweakInject/NukeWirelessInfo.plist"
INFO_PATCH = INFO_LIBRARY + ".roothidepatch"
ENTITLEMENTS = "usr/share/nukewireless-roothide/roothide.entitlements"


def read_zstd_tar(archive: bytes) -> list[tuple[tarfile.TarInfo, bytes | None]]:
    with zstd.ZstdDecompressor().stream_reader(io.BytesIO(archive)) as reader:
        expanded = reader.read()
    entries = []
    with tarfile.open(fileobj=io.BytesIO(expanded), mode="r:") as tf:
        for member in tf:
            payload = tf.extractfile(member).read() if member.isfile() else None
            if member.isfile() and len(payload) != member.size:
                raise ValueError(f"truncated tar member: {member.name}")
            entries.append((copy.copy(member), payload))
    return entries


def replace_once(data: bytes, before: bytes, after: bytes) -> bytes:
    if data.count(before) != 1:
        raise ValueError(f"expected one occurrence of {before!r}")
    return data.replace(before, after, 1)


def main() -> None:
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != EXPECTED_SOURCE_SHA256:
        raise ValueError("source deb differs from the known-working Nuke Wireless 1.0.25 package")
    info_binary = (ROOT / "prebuilt" / "NukeWirelessInfo_ios.dylib").read_bytes()
    if (b"https://buymeacoffee.com/gokuen" not in info_binary or
        b"NWInfoLinkTarget" not in info_binary or b"BSSID" not in info_binary):
        raise ValueError("Info extension binary does not match this source")

    parts = read_ar(original)
    control_entries = read_zstd_tar(get_tar_member(parts, "control.tar"))
    data_entries = read_zstd_tar(get_tar_member(parts, "data.tar"))
    control_names = {member.name.lstrip("./") for member, _ in control_entries}
    data_names = {member.name.lstrip("./") for member, _ in data_entries}
    if not {"control", "postinst"}.issubset(control_names):
        raise ValueError("missing package control files")
    required = {
        "Applications/HarpyReloaded.app/HarpyReloaded",
        "Applications/HarpyReloaded.app/CreditsAvatar.jpg",
        "usr/lib/TweakInject/HarpyRootHidePaths.dylib",
        "usr/lib/TweakInject/NukeWirelessPaths.dylib",
        ENTITLEMENTS,
    }
    if not required.issubset(data_names) or {INFO_LIBRARY, INFO_FILTER, INFO_PATCH} & data_names:
        raise ValueError("unexpected source package contents")

    for index, (member, payload) in enumerate(control_entries):
        name = member.name.lstrip("./")
        if name == "control":
            payload = replace_once(payload, b"Version: 1.0.25+rh25\n",
                                   b"Version: 1.0.25+rh25.1\n")
            member.size = len(payload)
            control_entries[index] = (member, payload)
        elif name == "postinst":
            payload = replace_once(payload,
                b"ldid -S /usr/lib/TweakInject/NukeWirelessPaths.dylib\n",
                b"ldid -S /usr/lib/TweakInject/NukeWirelessPaths.dylib\n"
                b"ldid -S /usr/lib/TweakInject/NukeWirelessInfo.dylib\n")
            member.size = len(payload)
            control_entries[index] = (member, payload)

    for index, (member, payload) in enumerate(data_entries):
        if member.name.lstrip("./") == ENTITLEMENTS:
            payload = replace_once(payload, b"</dict></plist>",
                b"<key>com.apple.developer.networking.wifi-info</key><true/>\n"
                b"</dict></plist>")
            member.size = len(payload)
            data_entries[index] = (member, payload)

    filter_data = next(payload for member, payload in data_entries
        if member.name.lstrip("./") == "usr/lib/TweakInject/NukeWirelessPaths.plist")
    data_entries.extend([
        regular(INFO_LIBRARY, info_binary, 0o755),
        regular(INFO_FILTER, filter_data),
        symlink(INFO_PATCH, "/usr/lib/DynamicPatches/AutoPatches.dylib"),
    ])

    for member, payload in control_entries + data_entries:
        if member.isfile() and len(payload) != member.size:
            raise ValueError(f"tar member size mismatch: {member.name}: {member.size} != {len(payload)}")

    output = pack_ar([
        ("debian-binary", parts["debian-binary"]),
        ("control.tar.gz", tar_bytes(control_entries)),
        ("data.tar.gz", tar_bytes(data_entries)),
    ])
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(output)
    print(OUTPUT)
    print("sha256", hashlib.sha256(output).hexdigest())


if __name__ == "__main__":
    main()
