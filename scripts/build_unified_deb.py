"""Combine current, manifest-verified app/worker candidates into one installer.

No native code is rebuilt or patched. Maintainer scripts remain archive data;
each original postinst runs in its own subshell so its exit cannot skip the other.
"""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

from build_manifest import ROOT, sha, source_hashes
from bluetooth_manifest import sources as bluetooth_sources
from build_compat_debs import VERSION as APP_VERSION
from build_bluetooth_deb import VERSION as WORKER_VERSION
from build_nuke_info_deb import read_tar
from install_layout import APP, EXECUTABLE, HELPERS
from compat_layout import SCHEMES, ordered_entries
from compat_manifest import compat_sources
from package_utils import get_tar_member, pack_ar, regular, read_ar, tar_bytes
from embedded_ui import require_embedded_ui

PACKAGE = "com.gokuencinar.nukewireless"
WORKER_PACKAGE = PACKAGE + ".bluetooth"
VERSION = APP_VERSION + "+bundle1"
INSTALLATION_POLICY = {"minimum_ios": None, "maximum_ios_exclusive": None, "binary_minimum_ios": "15.0",
                       "scope": "installer-only", "runtime_checks_unchanged": True}
PACKAGING_SOURCES = ["scripts/build_unified_deb.py", "scripts/package_utils.py", "scripts/compat_layout.py", "scripts/install_layout.py", "scripts/embedded_ui.py", "src/NWInstallLayout.h"]


def members(raw, archive):
    return {m.name.removeprefix("./").rstrip("/"): (m, data)
            for m, data in read_tar(get_tar_member(read_ar(raw), archive))}


def fields(control):
    result = {}
    for line in control.decode("utf-8").splitlines():
        if line.startswith((" ", "\t")) or ": " not in line:
            raise ValueError("unexpected control syntax")
        key, value = line.split(": ", 1)
        if key in result:
            raise ValueError("duplicate control field")
        result[key] = value
    return result


def load_package(path, scheme, worker=False):
    raw = path.read_bytes()
    report = json.loads(path.with_suffix(".manifest.json").read_text(encoding="utf-8"))
    _, _, architecture, _ = SCHEMES[scheme]
    version = WORKER_VERSION if worker else APP_VERSION
    if (report.get("package_sha256") != sha(raw) or report.get("scheme") != scheme
            or report.get("architecture") != architecture or report.get("version") != version):
        raise ValueError("package hash, version or bootstrap mismatch: " + path.name)
    data, control = members(raw, "data.tar"), members(raw, "control.tar")
    info = fields(control["control"][1])
    if (info["Package"] != (WORKER_PACKAGE if worker else PACKAGE)
            or info["Architecture"] != architecture or info["Version"] != version):
        raise ValueError("control identity mismatch")
    expected_control = {"control", "postinst"} if worker else {"control", "postinst", "prerm"}
    if set(control) != expected_control:
        raise ValueError("unhandled maintainer files")
    if worker:
        if report["sources"] != bluetooth_sources():
            raise ValueError("stale Bluetooth sources")
    elif (report["core"]["sources"] != source_hashes()
          or report["adapter"]["sources"] != compat_sources()):
        raise ValueError("stale app or adapter sources")
    return raw, report, data, control, info


def combined_postinst(app_script, worker_script):
    for script in (app_script, worker_script):
        if not script.startswith(b"#!/bin/sh\nset -e\n") or not script.endswith(b"exit 0\n"):
            raise ValueError("unexpected postinst contract")
    return (b"#!/bin/sh\nset -e\n# Sign and configure both components; fail if either fails.\n"
            b"(\n" + worker_script + b")\n(\n" + app_script + b")\nexit 0\n")


def build(app_path, worker_path, output, scheme):
    app_raw, app_report, app_data, app_control, control = load_package(app_path, scheme)
    worker_raw, worker_report, worker_data, worker_control, worker_info = load_package(worker_path, scheme, True)
    prefix, inject, architecture, _ = SCHEMES[scheme]
    # Verify the payload as well as the sidecar manifests before merging it.
    info = plistlib.loads(app_data[prefix + APP + "Info.plist"][1])
    if (info["NukeWirelessPackageScheme"] != scheme
            or info["CFBundleShortVersionString"] != APP_VERSION
            or info["NukeWirelessWorkerVersion"] != WORKER_VERSION
            or info.get("MinimumOSVersion") != INSTALLATION_POLICY["binary_minimum_ios"]
            or info.get("CFBundleExecutable") != EXECUTABLE
            or info["CFBundleIdentifier"] != "me.midnightchips.harpy-reloaded"):
        raise ValueError("app metadata mismatch")
    if info.get("NukeWirelessUIIntegration") != "embedded-required-v1":
        raise ValueError("app UI still depends on external tweak injection")
    executable = app_data[prefix + APP + EXECUTABLE][1]
    require_embedded_ui(executable)
    if sha(executable) != app_report["ui_integration"]["executable_sha256"]:
        raise ValueError("embedded app executable hash mismatch")
    if (sha(app_data[prefix + APP + "Frameworks/NukeWirelessInfo.dylib"][1]) != app_report["core"]["binary_sha256"]
            or sha(app_data[prefix + APP + "Frameworks/NukeWirelessPaths.dylib"][1]) != app_report["adapter"]["path_library_sha256"]
            or sha(app_data[prefix + HELPERS + "nw-hotspot"][1]) != app_report["core"]["hotspot_helper_sha256"]):
        raise ValueError("app payload mismatch")
    for name, folder in [("nwbt-run", "usr/bin/"), ("nwbt-inspect", "usr/bin/"),
                         ("NukeBluetoothBridge.dylib", "usr/lib/")]:
        if sha(worker_data[prefix + folder + name][1]) != worker_report["files"][name]:
            raise ValueError("Bluetooth payload mismatch")
    control["Version"] = VERSION
    # dpkg must transfer ownership from the standalone worker on upgrade.
    for field in ("Conflicts", "Replaces"):
        control[field] = ", ".join(filter(None, [control.get(field), WORKER_PACKAGE]))
    control["Provides"] = f"{WORKER_PACKAGE} (= {WORKER_VERSION})"
    # Retain both dependency sets, except the old installer-only iOS bounds.
    # Private Bluetooth transport admission remains in the unchanged binaries.
    for field in ("Depends", "Pre-Depends"):
        dependencies = list(dict.fromkeys(
            item.strip() for value in (control.get(field, ""), worker_info.get(field, ""))
            for item in value.split(",") if item.strip() and item.strip() not in {"firmware (>= 15.0)", "firmware (<< 19.0)"}))
        if dependencies:
            control[field] = ", ".join(dependencies)
    firmware = [item for item in control["Depends"].split(", ") if item.startswith("firmware")]
    if firmware:
        raise ValueError("unexpected firmware policy")
    control["Description"] = f"NukeWireless development diagnostic edition ({SCHEMES[scheme][3]}); includes Bluetooth worker"
    merged = list(app_data.values()) + list(worker_data.values())
    # Correct the standalone worker removal instruction now that it is bundled.
    readme = prefix + "usr/share/nukewireless-bluetooth/README.txt"
    previous = worker_data[readme][1]
    old = f"dpkg -r {WORKER_PACKAGE}".encode()
    if previous.count(old) != 1:
        raise ValueError("unexpected worker removal instruction")
    merged = [(m, data) for m, data in merged if m.name.removeprefix("./").rstrip("/") != readme]
    merged.append(regular(readme, previous.replace(old, f"dpkg -r {PACKAGE}".encode())))
    info_path = prefix + APP + "Info.plist"
    info.pop("MinimumOSVersion")
    merged = [(m, data) for m, data in merged if m.name.removeprefix("./").rstrip("/") != info_path]
    merged.append(regular(info_path, plistlib.dumps(info, fmt=plistlib.FMT_BINARY)))
    status_path = prefix + "usr/share/nukewireless-roothide/compatibility.json"
    status = json.loads(app_data[status_path][1].decode("utf-8"))
    if status.get("minimum_ios") != "15.0" or status.get("maximum_ios_exclusive") != "19.0":
        raise ValueError("unexpected input compatibility policy")
    status.update(maximum_ios_exclusive=None, installation_policy=INSTALLATION_POLICY)
    merged = [(m, data) for m, data in merged if m.name.removeprefix("./").rstrip("/") != status_path]
    merged.append(regular(status_path, (json.dumps(status, indent=2) + "\n").encode("utf-8")))
    provenance = {"package_version": VERSION, "app_version": APP_VERSION,
                  "worker_version": WORKER_VERSION, "scheme": scheme,
                  "source_commit": app_report["core"]["source_commit"],
                  "inputs": {"app": sha(app_raw), "bluetooth": sha(worker_raw)},
                  "native_payload_changed": False, "unified_installation_verified": False,
                  "installation_policy": INSTALLATION_POLICY,
                  "packaging_source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                  "packaging_sources": {name: sha((ROOT/name).read_bytes().replace(b"\r\n", b"\n")) for name in PACKAGING_SOURCES}}
    merged.append(regular(prefix + "usr/share/nukewireless-roothide/unified-package.json",
                          (json.dumps(provenance, indent=2) + "\n").encode("utf-8")))
    scripts = [regular("control", ("\n".join(f"{key}: {value}" for key, value in control.items()) + "\n").encode("utf-8")),
               regular("postinst", combined_postinst(app_control["postinst"][1], worker_control["postinst"][1]), 0o755),
               app_control["prerm"]]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(pack_ar([("debian-binary", b"2.0\n"),
                               ("control.tar.gz", tar_bytes(scripts)),
                               ("data.tar.gz", tar_bytes(ordered_entries(merged)))]))
    report = dict(provenance, package_sha256=sha(output.read_bytes()), architecture=architecture,
                  components={"app": app_report, "bluetooth": worker_report},
                  changed_payload_files=[readme, info_path, status_path], runtime_verified=False)
    output.with_suffix(".manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True, help="directory with both DEBs and manifests per scheme")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/diagnostic10-unified")
    parser.add_argument("--scheme", choices=["all", *SCHEMES], default="all")
    args = parser.parse_args()
    for scheme in SCHEMES if args.scheme == "all" else [args.scheme]:
        architecture = SCHEMES[scheme][2]
        destination = args.output / f"{PACKAGE}_{VERSION}_{architecture}.deb"
        report = build(args.inputs / f"{PACKAGE}_{APP_VERSION}_{architecture}.deb",
                       args.inputs / f"{WORKER_PACKAGE}_{WORKER_VERSION}_{architecture}.deb", destination, scheme)
        print(destination)
        print("SHA256", report["package_sha256"])
