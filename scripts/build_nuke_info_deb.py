"""Build the private development package from the pinned current baseline.

Archive scripts are data, never executed. The two stable path libraries and
network helpers remain byte-identical. SplashView loads the current logo and uses the already imported black color
getter. String lengths, stack/register layouts and scanner code are preserved.
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
from language_catalog import native_strings
from package_utils import directory, get_tar_member, pack_ar, read_ar, regular, tar_bytes
from startup_resources import patch_splash_resources

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.25+rh25.5~dev52"
EXPECTED_SOURCE_SHA256 = "83b8f4364194ecabda0e516659568e7e92af656c0cfa82222ccb596239bfc128"
EXPECTED_APP_SHA256 = "ea2cf47a8d473d83bbb029e211ec78b85bdb75b863f771c0b49bee4c17807d11"
APP = "Applications/HarpyReloaded.app/"
INFO_LIBRARY = "usr/lib/TweakInject/NukeWirelessInfo.dylib"
TEXT_EDITS = {
    b"Thank you for using Harpy!": b"Welcome to NukeWireless!",
    b"Harpy is licensed under the MIT license.": b"NukeWireless uses the MIT license.",
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


def patch_app_signing_identity(script):
    original = b'''for executable in "$APP" "$BASE/aegis" "$BASE/arp-scan" "$BASE/arpspoof"; do
    ldid -Hsha256 -M "-S$ENT" "$executable"
done'''
    corrected = b'''ldid -Hsha256 -M -Ime.midnightchips.harpy-reloaded "-S$ENT" "$APP"
for executable in "$BASE/aegis" "$BASE/arp-scan" "$BASE/arpspoof"; do
    ldid -Hsha256 -M "-S$ENT" "$executable"
done'''
    if script.count(original) != 1:
        raise ValueError("unexpected baseline signing script")
    return script.replace(original, corrected, 1)

def build(source, artifact, output):
    raw = source.read_bytes()
    if sha(raw) != EXPECTED_SOURCE_SHA256:
        raise ValueError("baseline must be the current pinned rh25.3 package")
    library = (artifact / "NukeWirelessInfo_ios.dylib").read_bytes()
    manifest = json.loads((artifact / "build-manifest.json").read_text(encoding="utf-8"))
    if manifest["sources"] != source_hashes() or manifest["binary_sha256"] != sha(library):
        raise ValueError("stale or mismatched compiled artifact; rebuild current sources")
    if manifest["version"] != VERSION or b"NWBuild-rh25.5-dev52" not in library:
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
    startup_image = original[APP + "NukeWirelessIcon.png"]
    expected_startup = {"NWBootPic.png": sha(startup_image)}
    if manifest.get("startup_files") != expected_startup or any(
        sha((artifact / name).read_bytes()) != digest for name, digest in expected_startup.items()
    ):
        raise ValueError("missing or mismatched inspected startup resources")
    metadata = plistlib.loads(original[APP + "Info.plist"])
    metadata.update(CFBundleDisplayName="NukeWireless", CFBundleName="NukeWireless",
                    CFBundleShortVersionString=VERSION, CFBundleVersion="25.5.52",
                    CFBundleDevelopmentRegion="en", CFBundleLocalizations=["en", "es"],
                    NSBluetoothAlwaysUsageDescription="Scan nearby BLE devices / Escanear dispositivos BLE cercanos.")
    metadata.pop("UILaunchScreen", None)
    metadata["UILaunchStoryboardName"] = "NukeLaunch"
    metadata["CFBundleIcons~ipad"] = metadata["CFBundleIcons"]
    replacement = {
        INFO_LIBRARY: library,
        APP + "HarpyReloaded": patch_splash_resources(patch_visible_text(executable)),
        APP + "Info.plist": plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY),
    }
    for i,(member,data) in enumerate(entries):
        name = member.name.lstrip("./")
        if name in replacement:
            data = replacement[name]; member.size = len(data); entries[i] = (member,data)
    entries.append(regular(APP + "NWBootPic.png", startup_image))
    launch = artifact / "NukeLaunch.storyboardc"
    launch_files = {p.relative_to(launch).as_posix(): sha(p.read_bytes()) for p in sorted(launch.rglob("*")) if p.is_file()}
    if not launch_files or launch_files != manifest.get("launch_files"):
        raise ValueError("missing or mismatched launch storyboard")
    entries.append(directory(APP + "NukeLaunch.storyboardc/"))
    for path in sorted(launch.rglob("*")):
        name = APP + "NukeLaunch.storyboardc/" + path.relative_to(launch).as_posix()
        entries.append(directory(name + "/") if path.is_dir() else regular(name, path.read_bytes()))
    bundle = APP + "NukeWirelessResources.bundle/"
    entries += [directory(bundle), directory(bundle + "en.lproj/"),
                directory(bundle + "es.lproj/"),
                regular(bundle + "Info.plist", plistlib.dumps({
        "CFBundleIdentifier":"app.nukewireless.resources", "CFBundleName":"NukeWireless",
        "CFBundleDevelopmentRegion":"en", "CFBundleLocalizations":["en","es"], "CFBundlePackageType":"BNDL",
    })), regular(bundle + "oui_vendors.plist", original["usr/share/nukewireless-roothide/oui_vendors.plist"])]
    entries.append(directory(bundle + "brands/"))
    for path in sorted((ROOT / "resources/brands").iterdir()):
        if path.is_file(): entries.append(regular(bundle + "brands/" + path.name, path.read_bytes()))
    for path in sorted((ROOT / "resources").rglob("*.strings")):
        entries.append(regular(bundle + path.relative_to(ROOT / "resources").as_posix(),path.read_bytes()))
    for language in ["en", "es"]:
        native = native_strings(language)
        entries.append(regular(bundle + language + ".lproj/Native.strings", native))
        main = APP + language + ".lproj/"
        if main not in original: entries.append(directory(main))
        entries.append(regular(main + "Localizable.strings", native))
    entries.append(regular(bundle + "CreditsAvatar.png", (ROOT / "resources/CreditsAvatar.png").read_bytes()))
    for i,(member,data) in enumerate(control):
        if member.name.lstrip("./") == "postinst":
            data = patch_app_signing_identity(data)
            member.size = len(data); control[i] = (member,data)
        if member.name.lstrip("./") == "control":
            before = b"Version: 1.0.25+rh25.3\n"
            if data.count(before) != 1: raise ValueError("unexpected baseline control")
            data = data.replace(before, f"Version: {VERSION}\n".encode())
            data = data.replace(b"Name: Nuke Wireless\n", b"Name: NukeWireless\n")
            data = data.replace(b"Description: Nuke Wireless ", b"Description: NukeWireless ")
            data = data.replace(b"Depends: firmware (>= 16.0)", b"Depends: firmware (>= 16.3)")
            member.size = len(data); control[i] = (member,data)
    for member,data in control + entries:
        if member.isfile() and member.size != len(data): raise ValueError("wrong member size")
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(pack_ar([("debian-binary",parts["debian-binary"]),
        ("control.tar.gz",tar_bytes(control)),("data.tar.gz",tar_bytes(entries))]))
    report = {"version":VERSION,"baseline_sha256":sha(raw),"package_sha256":sha(output.read_bytes()),
              "extension":manifest, "app_before":sha(executable),"app_after":sha(replacement[APP+"HarpyReloaded"]),
              "changed_existing_files": sorted(replacement), "changed_control_files": ["control", "postinst"],
              "app_signing_identifier": "me.midnightchips.harpy-reloaded", "release_published":False}
    output.with_suffix(".manifest.json").write_text(json.dumps(report,indent=2)+"\n", encoding="utf-8")
    print(output); print("sha256",report["package_sha256"])
    return report

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline",type=Path)
    parser.add_argument("--artifact",type=Path,default=ROOT / "build/audit")
    parser.add_argument("--output",type=Path,default=ROOT / "dist" / f"com.gokuencinar.nukewireless_{VERSION}_iphoneos-arm64e.deb")
    args=parser.parse_args(); build(args.baseline,args.artifact,args.output)
