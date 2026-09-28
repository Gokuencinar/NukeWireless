"""Build the private development package from the pinned current baseline.

Archive scripts are data, never executed. The two stable path libraries and
network helpers remain byte-identical. The app receives only two length-preserving
visible text substitutions; no instructions, identifiers or Swift layouts change.
"""
from __future__ import annotations
import argparse
import copy
import io
import json
from pathlib import Path
import plistlib
import tarfile
from build_manifest import source_hashes, sha
from package_utils import directory, get_tar_member, pack_ar, read_ar, regular, tar_bytes

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.25+rh25.5~dev5"
EXPECTED_SOURCE_SHA256 = "83b8f4364194ecabda0e516659568e7e92af656c0cfa82222ccb596239bfc128"
EXPECTED_APP_SHA256 = "ea2cf47a8d473d83bbb029e211ec78b85bdb75b863f771c0b49bee4c17807d11"
APP = "Applications/HarpyReloaded.app/"
INFO_LIBRARY = "usr/lib/TweakInject/NukeWirelessInfo.dylib"
TEXT_EDITS = {
    b"Thank you for using Harpy!": b"Welcome to Nuke Wireless!",
    b"Harpy is licensed under the MIT license.": b"Nuke Wireless uses the MIT license.",
}

def read_tar(data):
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as tf:
        result = [(copy.copy(m), tf.extractfile(m).read() if m.isfile() else None) for m in tf]
    names = [m.name.lstrip("./") for m, _ in result]
    if len(names) != len(set(names)):
        raise ValueError("duplicate archive member")
    return result

def patch_visible_text(binary):
    for old, new in TEXT_EDITS.items():
        if len(new) > len(old) or binary.count(old + b"\0") != 1:
            raise ValueError("visible text ABI does not match baseline")
        # Native Swift strings encode their lengths in instructions: keep byte count.
        binary = binary.replace(old + b"\0", new.ljust(len(old), b" ") + b"\0", 1)
    return binary

def build(source, artifact, output):
    raw = source.read_bytes()
    if sha(raw) != EXPECTED_SOURCE_SHA256:
        raise ValueError("baseline must be the current pinned rh25.3 package")
    library = (artifact / "NukeWirelessInfo_ios.dylib").read_bytes()
    manifest = json.loads((artifact / "build-manifest.json").read_text())
    if manifest["sources"] != source_hashes() or manifest["binary_sha256"] != sha(library):
        raise ValueError("stale or mismatched compiled artifact; rebuild current sources")
    if manifest["version"] != VERSION or b"NWBuild-rh25.5-dev5" not in library:
        raise ValueError("wrong development library version")
    if any(x in library for x in (b"requestWhenInUseAuthorization", b"requestAlwaysAuthorization", b"CLLocationManager")):
        raise ValueError("unexpected location-permission API")
    parts = read_ar(raw)
    control = read_tar(get_tar_member(parts, "control.tar"))
    entries = read_tar(get_tar_member(parts, "data.tar"))
    original = {m.name.lstrip("./"): data for m,data in entries}
    executable = original[APP + "HarpyReloaded"]
    if sha(executable) != EXPECTED_APP_SHA256 or executable[0xc5a8:0xc5b8] != bytes.fromhex("ffc301d1fa6702a9f85f03a9f65704a9"):
        raise ValueError("incompatible native Swift refresh ABI")
    metadata = plistlib.loads(original[APP + "Info.plist"])
    metadata.update(CFBundleDisplayName="Nuke Wireless", CFBundleName="Nuke Wireless",
                    CFBundleShortVersionString=VERSION, CFBundleVersion="25.5.3")
    metadata["CFBundleIcons~ipad"] = metadata["CFBundleIcons"]
    replacement = {
        INFO_LIBRARY: library,
        APP + "HarpyReloaded": patch_visible_text(executable),
        APP + "Info.plist": plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY),
    }
    for i,(member,data) in enumerate(entries):
        name = member.name.lstrip("./")
        if name in replacement:
            data = replacement[name]; member.size = len(data); entries[i] = (member,data)
    bundle = APP + "NukeWirelessResources.bundle/"
    entries += [directory(bundle), directory(bundle + "en.lproj/"),
                directory(bundle + "es.lproj/"),
                regular(bundle + "Info.plist", plistlib.dumps({
        "CFBundleIdentifier":"app.nukewireless.resources", "CFBundleName":"Nuke Wireless",
        "CFBundleDevelopmentRegion":"en", "CFBundleLocalizations":["en","es"], "CFBundlePackageType":"BNDL",
    })), regular(bundle + "oui_vendors.plist", original["usr/share/nukewireless-roothide/oui_vendors.plist"])]
    for path in sorted((ROOT / "resources").rglob("*.strings")):
        entries.append(regular(bundle + path.relative_to(ROOT / "resources").as_posix(),path.read_bytes()))
    entries.append(regular(bundle + "CreditsAvatar.png", (ROOT / "resources/CreditsAvatar.png").read_bytes()))
    for i,(member,data) in enumerate(control):
        if member.name.lstrip("./") == "control":
            before = b"Version: 1.0.25+rh25.3\n"
            if data.count(before) != 1: raise ValueError("unexpected baseline control")
            data = data.replace(before, f"Version: {VERSION}\n".encode())
            data = data.replace(b"Depends: firmware (>= 16.0)", b"Depends: firmware (>= 16.3)")
            member.size = len(data); control[i] = (member,data)
    for member,data in control + entries:
        if member.isfile() and member.size != len(data): raise ValueError("wrong member size")
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(pack_ar([("debian-binary",parts["debian-binary"]),
        ("control.tar.gz",tar_bytes(control)),("data.tar.gz",tar_bytes(entries))]))
    report = {"version":VERSION,"baseline_sha256":sha(raw),"package_sha256":sha(output.read_bytes()),
              "extension":manifest, "app_before":sha(executable),"app_after":sha(replacement[APP+"HarpyReloaded"]),
              "changed_existing_files": sorted(replacement), "release_published":False}
    output.with_suffix(".manifest.json").write_text(json.dumps(report,indent=2)+"\n")
    print(output); print("sha256",report["package_sha256"])
    return report

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline",type=Path)
    parser.add_argument("--artifact",type=Path,default=ROOT / "build/audit")
    parser.add_argument("--output",type=Path,default=ROOT / "dist" / f"com.gokuencinar.nukewireless_{VERSION}_iphoneos-arm64e.deb")
    args=parser.parse_args(); build(args.baseline,args.artifact,args.output)
