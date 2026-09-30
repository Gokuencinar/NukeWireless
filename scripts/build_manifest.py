"""Record precise source and binary hashes for the private build artifact."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['src/NukeWirelessInfo.m', 'src/NWScanBridge.m', 'src/NWScanBridge.h',
           'src/NWResources.m', 'src/NWResources.h', 'src/NWPolicy.c', 'src/NWPolicy.h',
           'src/NWLanguage.m', 'src/NWLanguage.h',
           'src/NWRefreshThunk.S', 'scripts/build_extension.sh', 'resources/NukeLaunch.storyboard']
def sha(data):
    return hashlib.sha256(data).hexdigest()
def source_hashes():
    return {name: sha((ROOT / name).read_bytes().replace(b'\r\n', b'\n')) for name in SOURCES}
if __name__ == '__main__':
    out = ROOT / 'build/audit'
    (out / 'build-manifest.json').write_text(json.dumps({
        'sources': source_hashes(), 'binary_sha256': sha((out / 'NukeWirelessInfo_ios.dylib').read_bytes()),
        'launch_files': {p.relative_to(out / 'NukeLaunch.storyboardc').as_posix(): sha(p.read_bytes())
                         for p in sorted((out / 'NukeLaunch.storyboardc').rglob('*')) if p.is_file()},
        'version': '1.0.25+rh25.5~dev16', 'target': 'arm64-ios16.3',
    }, indent=2) + '\n')
