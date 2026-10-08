"""Record precise source and binary hashes for the private build artifact."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['src/NukeWirelessInfo.m', 'src/NWMainTabs.m', 'src/NWMainTabs.h', 'src/NWAppearance.m', 'src/NWAppearance.h',
           'src/NWDeviceBrowser.m', 'src/NWDeviceBrowser.h',
           'src/NWBluetooth.m', 'src/NWBluetooth.h', 'src/NWBluetoothCatalog.m', 'src/NWBluetoothCatalog.h', 'src/NWDeviceCatalog.h', 'src/NWCatalogProfiles.h', 'src/NWBluetoothLimits.h',
           'src/NWBLE.m', 'src/NWBLE.h', 'src/NWBLEAdvertisement.m', 'src/NWBLEAdvertisement.h',
           'resources/en.lproj/Localizable.strings', 'resources/es.lproj/Localizable.strings', 'src/NWScanBridge.m', 'src/NWScanBridge.h',
           'src/NWResources.m', 'src/NWResources.h', 'src/NWPolicy.c', 'src/NWPolicy.h',
           'src/NWLanguage.m', 'src/NWLanguage.h',
           'src/NWRefreshThunk.S', 'scripts/build_extension.sh', 'resources/NukeLaunch.storyboard',
           'scripts/startup_resources.py',
           'resources/startup/NukeWirelessIcon.png']
SOURCES += [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / 'resources/brands').iterdir()) if p.is_file()]

def sha(data):
    return hashlib.sha256(data).hexdigest()
def source_hashes():
    return {name: sha((ROOT / name).read_bytes() if name.endswith(('.car', '.png', '.pdf')) else
                      (ROOT / name).read_bytes().replace(b'\r\n', b'\n')) for name in SOURCES}
if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', choices=['arm64-ios16.3', 'arm64-ios15.0'], default='arm64-ios16.3')
    args = parser.parse_args()
    out = ROOT / 'build/audit'
    (out / 'build-manifest.json').write_text(json.dumps({
        'sources': source_hashes(), 'binary_sha256': sha((out / 'NukeWirelessInfo_ios.dylib').read_bytes()),
        'launch_files': {p.relative_to(out / 'NukeLaunch.storyboardc').as_posix(): sha(p.read_bytes())
                         for p in sorted((out / 'NukeLaunch.storyboardc').rglob('*')) if p.is_file()},
        'startup_files': {name: sha((out / name).read_bytes()) for name in ['NWBootPic.png']},
        'version': '1.0.25+rh25.5~dev52', 'target': args.target,
    }, indent=2) + '\n', encoding='utf-8')
