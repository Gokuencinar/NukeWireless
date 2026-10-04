import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['src/bluetooth/NWBTBridge.h', 'src/bluetooth/NWBTNative.h', 'src/bluetooth/NWBTBridge.m', 'src/bluetooth/NWBTController.m', 'src/bluetooth/NWBTL2Ping.m',
           'src/bluetooth/NWBTInspector.m', 'scripts/build_bluetooth_inspector.sh',
           'src/bluetooth/NWBTRunner.m',
           'scripts/bluetooth_manifest.py']

def sha(data): return hashlib.sha256(data).hexdigest()
def sources(): return {name: sha((ROOT / name).read_bytes().replace(b'\r\n', b'\n')) for name in SOURCES}

if __name__ == '__main__':
    output = ROOT / 'build/bluetooth'
    report = {'version': '0.0.3~app3', 'target': 'arm64-ios15.0', 'sources': sources(),
              'files': {name: sha((output / name).read_bytes()) for name in ['NukeBluetoothBridge.dylib', 'nwbt-inspect', 'nwbt-run']},
              'l2ping_implemented': True, 'runtime_verified': False}
    (output / 'bluetooth-manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
