"""Build three isolated, experimental packages from the pinned functional base.

Recompiles the recovered adapter rather than lowering deployment metadata in
old iOS 16.3 libraries. Maintainer scripts remain archive data on the build host.
"""
import argparse
import copy
import json
import plistlib
import tempfile
from pathlib import Path
from build_manifest import ROOT, sha
from build_nuke_info_deb import build, read_tar, APP, EXPECTED_SOURCE_SHA256, hotspot_prerm
from compat_manifest import compat_sources
from compat_macho import compatible_aegis, inspect, thin_arm64
from compat_layout import SCHEMES, ordered_entries
from package_utils import regular, read_ar, get_tar_member, pack_ar, tar_bytes

VERSION = "2.0.0~diagnostic3"

def maintainer_script(prefix, inject):
    root = "/" + prefix.rstrip("/") if prefix else ""
    return f'''#!/bin/sh
set -e
ENT={root}/usr/share/nukewireless-roothide/roothide.entitlements
APP={root}/Applications/HarpyReloaded.app/HarpyReloaded
BASE={root}/usr/libexec/harpy-reloaded
ldid -Hsha256 -M -Ime.midnightchips.harpy-reloaded "-S$ENT" "$APP"
for executable in "$BASE/aegis" "$BASE/arp-scan" "$BASE/arpspoof"; do
    ldid -Hsha256 -M "-S$ENT" "$executable"
done
ldid -S {root}/{inject}/NukeWirelessPaths.dylib
ldid -S {root}/{inject}/NukeWirelessInfo.dylib
ldid -Hsha256 -S{root}/usr/share/nukewireless-roothide/hotspot.entitlements "$BASE/nw-hotspot"
chown root:wheel "$BASE/nw-hotspot"
chmod 4755 "$BASE/nw-hotspot"
chown root:wheel "$BASE/aegis"
chmod 6755 "$BASE/aegis"
if command -v uicache >/dev/null 2>&1; then
    uicache -p {root}/Applications/HarpyReloaded.app || true
fi
exit 0
'''.encode()

def package(scheme, core, artifact, output):
    prefix, inject, architecture, label = SCHEMES[scheme]
    parts = read_ar(core)
    entries = read_tar(get_tar_member(parts, "data.tar"))
    original = {m.name.removeprefix("./"): data for m, data in entries}
    manifest = json.loads((artifact / "compat-manifest.json").read_text(encoding="utf-8"))
    paths = (artifact / "NukeWirelessPaths_ios.dylib").read_bytes()
    core_manifest = json.loads((artifact / "build-manifest.json").read_text(encoding="utf-8"))
    if (manifest["sources"] != compat_sources() or manifest["path_library_sha256"] != sha(paths)
            or manifest["target"] != "arm64-ios15.0" or core_manifest["target"] != manifest["target"]):
        raise ValueError("mismatched compatibility build; rebuild the current sources")
    metadata = plistlib.loads(original[APP + "Info.plist"])
    metadata.update(CFBundleShortVersionString=VERSION, CFBundleVersion="20003", NukeWirelessPackageScheme=scheme, MinimumOSVersion="15.0")
    replacement = {
        APP + "Info.plist": plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY),
        "usr/lib/TweakInject/NukeWirelessPaths.dylib": paths,
        "usr/libexec/harpy-reloaded/aegis": compatible_aegis(original["usr/libexec/harpy-reloaded/aegis"]),
    }
    for name in ["arp-scan", "arpspoof"]:
        path = "usr/libexec/harpy-reloaded/" + name
        replacement[path] = thin_arm64(original[path])
    checks = {}; final = []
    for member, data in entries:
        name = member.name.removeprefix("./").strip("/")
        if not name or name.startswith(("usr/lib/TweakInject/HarpyRootHidePaths", "usr/share/harpy-reloaded-roothide")):
            continue
        if scheme != "roothide" and name.endswith(".roothidepatch"):
            continue
        if name in replacement:
            data = replacement[name]
        if member.isfile() and data[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
            checks[name] = inspect(data)
        if name == "usr/lib/TweakInject" or name.startswith("usr/lib/TweakInject/"):
            name = inject + name[len("usr/lib/TweakInject"):]
        member = copy.copy(member); member.name = "./" + prefix + name
        if member.isfile(): member.size = len(data)
        final.append((member, data))
    # Explicit status included with every candidate; no unsupported validation claim.
    report = {"version": VERSION, "scheme": scheme, "bootstrap": label,
              "architecture": architecture, "minimum_ios": "15.0", "maximum_ios_exclusive": "19.0",
              "runtime_verified": False, "source_core_version": core_manifest["version"],
              "app_signing_identifier": "me.midnightchips.harpy-reloaded",
              "bluetooth_native_verified_environment": {"machine": "iPhone11,2", "ios": "16.3.1", "bootstrap": "roothide"},
              "bluetooth_native_admission_policy": "skywalk-runtime-contract-v1",
              "removed_duplicate_adapter": "HarpyRootHidePaths.dylib",
              "native_files": checks, "adapter": manifest,
              "core": core_manifest, "baseline_sha256": EXPECTED_SOURCE_SHA256,
              "development_core_sha256": sha(core)}
    status_path = prefix + "usr/share/nukewireless-roothide/compatibility.json"
    final.append(regular(status_path, (json.dumps(report, indent=2) + "\n").encode()))
    predepends = "Pre-Depends: rootless-compat (>= 0.9)\n" if scheme == "roothide" else ""
    hooks = "ellekit" if scheme == "roothide" else "mobilesubstrate"
    control = f'''Package: com.gokuencinar.nukewireless
Name: NukeWireless Dev
Version: {VERSION}
Architecture: {architecture}
Author: GokuEn
Maintainer: GokuEn
Section: Utilities
{predepends}Depends: firmware (>= 15.0), firmware (<< 19.0), ldid, arpoison, network-cmds, {hooks}
Conflicts: xyz.cypwn.harpy-reloaded
Replaces: xyz.cypwn.harpy-reloaded
Description: NukeWireless iOS 15-18 development diagnostic edition ({label})
'''.encode()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / f"com.gokuencinar.nukewireless_{VERSION}_{architecture}.deb"
    destination.write_bytes(pack_ar([("debian-binary", b"2.0\n"),
        ("control.tar.gz", tar_bytes([regular("control", control), regular("postinst", maintainer_script(prefix, inject), 0o755), regular("prerm", hotspot_prerm(prefix), 0o755)])),
        ("data.tar.gz", tar_bytes(ordered_entries(final)))]))
    report["package_sha256"] = sha(destination.read_bytes())
    destination.with_suffix(".manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(destination)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/diagnostic3")
    parser.add_argument("--scheme", choices=["all", *SCHEMES], default="all")
    args = parser.parse_args()
    # The guarded startup resource/Swift patches remain guarded in the original builder.
    (ROOT / "work").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nuke-compat-", dir=ROOT / "work") as temporary:
        staged = Path(temporary) / "core.deb"
        build(args.baseline, args.artifact, staged)
        for scheme in (SCHEMES if args.scheme == "all" else [args.scheme]):
            package(scheme, staged.read_bytes(), args.artifact, args.output)
