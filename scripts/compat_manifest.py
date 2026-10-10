"""Provenance of the separately compiled compatibility adapter."""
import json
from build_manifest import ROOT, sha

SOURCES = ["src/NWLegacyABI.h", "src/NWInstallLayout.h", "scripts/install_layout.py", "src/NWRouteNeighbors.h", "tests/test_route_neighbors.c", "src/hotspot/vendor/net/route.h", "src/compat/NWBootstrapPaths.c", "scripts/build_compat.sh",
           "scripts/compat_manifest.py", "scripts/build_compat_debs.py", "scripts/compat_macho.py",
           "scripts/compat_layout.py", "scripts/embedded_ui.py", "scripts/build_bluetooth_deb.py",
           "scripts/test_ui_simulator.sh", ".github/workflows/compat-build.yml"]

def compat_sources():
    return {name: sha((ROOT / name).read_bytes().replace(b"\r\n", b"\n")) for name in SOURCES}

if __name__ == "__main__":
    out = ROOT / "build/audit"
    (out / "compat-manifest.json").write_text(json.dumps({
        "sources": compat_sources(), "target": "arm64-ios15.0",
        "path_library_sha256": sha((out / "NukeWirelessPaths_ios.dylib").read_bytes()),
        "recovered_commit": "29614397b9b3744f65bfa00aefaa734c3477b9d0",
        "recovered_prebuilt_sha256": "33244c638df562b6a16899a82e0fb7045fc96713ac276f4069037941c403db78",
        "runtime_verified": False,
    }, indent=2) + "\n", encoding="utf-8")
