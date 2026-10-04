"""Package the isolated RootHide transport inspector and bounded echo module."""
import argparse
import json
import plistlib
import struct
from pathlib import Path
from bluetooth_manifest import ROOT, sha, sources
from compat_macho import inspect
from package_utils import directory, regular, pack_ar, tar_bytes

VERSION = '0.0.2~probe8'
PACKAGE_VERSION = VERSION
ROOTHIDE_ENTITLEMENTS = {
    'platform-application': True,
    'com.apple.private.security.no-sandbox': True,
    'com.apple.private.security.storage.AppBundles': True,
    'com.apple.private.security.storage.AppDataContainers': True,
    'com.apple.driver.AppleBluetoothModule.user-access': True,
    'com.apple.driver.AppleConvergedIPC.user-access': True,
    'com.apple.security.exception.iokit-user-client-class': [
        'AppleBTHciUC', 'AppleBTMgmtUC', 'AppleConvergedIPCUserClient'],
}

def inspect_tool(data):
    if data[:4] != bytes.fromhex('cffaedfe') or struct.unpack_from('<II', data, 4) != (0x100000c, 0):
        raise ValueError('expected arm64 device inspector')
    count, length = struct.unpack_from('<II', data, 16)
    if count > 1024 or 32 + length > len(data): raise ValueError('invalid Mach-O header')
    result = {'architecture': 'arm64', 'minimum_ios': [], 'loads': []}
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > 32 + length: raise ValueError('invalid Mach-O command')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<II', data, offset + 8)
            if platform != 2: raise ValueError('expected iOS device target')
            result['minimum_ios'].append(minimum)
        if command in (0xc, 0x80000018, 0x8000001f, 0x80000023):
            start = struct.unpack_from('<I', data, offset + 8)[0]
            name = data[offset + start:offset + size].split(b'\0')[0].decode()
            if not name.startswith(('/System/Library/', '/usr/lib/')) and name != '@rpath/NukeBluetoothBridge.dylib':
                raise ValueError('unexpected linked library: ' + name)
            result['loads'].append(name)
        offset += size
    if not result['minimum_ios'] or max(result['minimum_ios']) > 15 << 16:
        raise ValueError('inspector minimum iOS mismatch')
    if '@rpath/NukeBluetoothBridge.dylib' not in result['loads']: raise ValueError('companion library not linked')
    return result

def build(artifact, output):
    report = json.loads((artifact / 'bluetooth-manifest.json').read_text(encoding='utf-8'))
    if report['version'] != VERSION or report['sources'] != sources():
        raise ValueError('stale Bluetooth inspector sources')
    library = (artifact / 'NukeBluetoothBridge.dylib').read_bytes()
    tool = (artifact / 'nwbt-inspect').read_bytes()
    for name, data in [('NukeBluetoothBridge.dylib', library), ('nwbt-inspect', tool)]:
        if sha(data) != report['files'][name]: raise ValueError('artifact hash mismatch')
        report[name + '_macho'] = inspect(data) if name.endswith('.dylib') else inspect_tool(data)
    control = f'''Package: com.gokuencinar.nukewireless.bluetooth
Name: NukeWireless Bluetooth Bridge (Research)
Version: {PACKAGE_VERSION}
Architecture: iphoneos-arm64e
Section: Development
Maintainer: Gokuencinar
Author: Gokuencinar
Depends: firmware (>= 15.0), firmware (<< 19.0), rootless-compat, ldid
Description: Experimental Bluetooth transport research for NukeWireless. Bounded five-echo L2CAP diagnostic restricted to the inspected iPhone XS / iOS 16.3.1. Requires exclusive transport ownership and external service recovery. Runtime verification pending.
'''.encode()
    postinst = b'''#!/bin/sh
set -e
ldid -Hsha256 -M -S/usr/share/nukewireless-bluetooth/inspector.entitlements /usr/bin/nwbt-inspect
ldid -Hsha256 -S /usr/lib/NukeBluetoothBridge.dylib
exit 0
'''
    entries = [directory(path) for path in ['usr', 'usr/bin', 'usr/lib', 'usr/share', 'usr/share/nukewireless-bluetooth']]
    entries += [regular('usr/bin/nwbt-inspect', tool, 0o755),
                regular('usr/lib/NukeBluetoothBridge.dylib', library, 0o755),
                regular('usr/share/nukewireless-bluetooth/inspector.entitlements', plistlib.dumps(ROOTHIDE_ENTITLEMENTS)),
                regular('usr/share/nukewireless-bluetooth/build-manifest.json', json.dumps(report, indent=2).encode()),
                regular('usr/share/nukewireless-bluetooth/README.txt', b'Run nwbt-inspect --inspect for passive inspection. Experimental nwbt-inspect --l2ping ADDRESS --exclusive submits five small echoes. Only iPhone XS / iOS 16.3.1 is admitted. Bluetooth must be off in Settings, HCI/ACL ownership exclusive, and independent service recovery scheduled by the operator. No service manipulation or app injection in this library. Runtime verification pending. Remove with dpkg -r com.gokuencinar.nukewireless.bluetooth.\n')]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(pack_ar([('debian-binary', b'2.0\n'),
        ('control.tar.gz', tar_bytes([regular('control', control), regular('postinst', postinst, 0o755)])),
        ('data.tar.gz', tar_bytes(entries))]))
    report['package_sha256'] = sha(output.read_bytes())
    report['package_version'] = PACKAGE_VERSION
    report['runtime_verified'] = False
    output.with_suffix('.manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(output); print('SHA256', report['package_sha256'])

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / f'dist/bluetooth/com.gokuencinar.nukewireless.bluetooth_{PACKAGE_VERSION}_iphoneos-arm64e.deb')
    args = parser.parse_args(); build(args.artifact, args.output)
