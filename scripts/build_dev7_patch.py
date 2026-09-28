"""Apply the verified RootHide refresh fix to the pinned dev6 iOS binary.

GitHub Actions cannot currently start a macOS runner on this account. This
length-preserving patch changes the dyld image index from 0 to 1 in the exact
dev6 binary whose index-1 diagnostic build completed a second scan on-device.
"""
from __future__ import annotations

import json
import plistlib
from pathlib import Path

from build_manifest import sha
from build_nuke_info_deb import APP, INFO_LIBRARY, read_tar
from package_utils import get_tar_member, pack_ar, read_ar, tar_bytes

ROOT = Path(__file__).resolve().parents[1]
OLD_VERSION = '1.0.25+rh25.5~dev6'
VERSION = '1.0.25+rh25.5~dev7'
SOURCE = ROOT / f'dist/com.gokuencinar.nukewireless_{OLD_VERSION}_iphoneos-arm64e.deb'
OUTPUT = ROOT / f'dist/com.gokuencinar.nukewireless_{VERSION}_iphoneos-arm64e.deb'
SOURCE_SHA256 = 'f3aac3eeaaf5c22653dc1d5e0728d739f93567551087290639099373220818ff'
LIBRARY_SHA256 = '3906d3f91182e0fcfcf2f5e4033b3b94f800630742bcf2b936ef24d308e1c303'
PATCH_OFFSET = 0x7ecc
OLD_INSTRUCTION = bytes.fromhex('00008052')  # mov w0, #0
NEW_INSTRUCTION = bytes.fromhex('20008052')  # mov w0, #1
STRINGS = {
    b'NWBuild-rh25.5-dev6': b'NWBuild-rh25.5-dev7',
    OLD_VERSION.encode(): VERSION.encode(),
    b'Nuke Wireless: extension dev6 loaded': b'Nuke Wireless: extension dev7 loaded',
}


def patch_library(library: bytes) -> bytes:
    if sha(library) != LIBRARY_SHA256 or library[PATCH_OFFSET:PATCH_OFFSET + 4] != OLD_INSTRUCTION:
        raise ValueError('unexpected dev6 library')
    result = bytearray(library)
    result[PATCH_OFFSET:PATCH_OFFSET + 4] = NEW_INSTRUCTION
    for before, after in STRINGS.items():
        if len(before) != len(after) or result.count(before + b'\0') != 1:
            raise ValueError('unexpected development-version string')
        result = result.replace(before + b'\0', after + b'\0', 1)
    return bytes(result)


def build(source: Path = SOURCE, output: Path = OUTPUT) -> dict:
    raw = source.read_bytes()
    if sha(raw) != SOURCE_SHA256:
        raise ValueError('unexpected dev6 package')
    parts = read_ar(raw)
    control = read_tar(get_tar_member(parts, 'control.tar'))
    data = read_tar(get_tar_member(parts, 'data.tar'))
    edits = []
    for index, (member, body) in enumerate(data):
        name = member.name.lstrip('./')
        if name == INFO_LIBRARY:
            body = patch_library(body)
        elif name == APP + 'Info.plist':
            info = plistlib.loads(body)
            if info['CFBundleShortVersionString'] != OLD_VERSION:
                raise ValueError('unexpected app version')
            info['CFBundleShortVersionString'] = VERSION
            info['CFBundleVersion'] = '25.5.7'
            body = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
        else:
            continue
        member.size = len(body)
        data[index] = member, body
        edits.append(name)
    for index, (member, body) in enumerate(control):
        if member.name.lstrip('./') != 'control':
            continue
        before = f'Version: {OLD_VERSION}\n'.encode()
        if body.count(before) != 1:
            raise ValueError('unexpected control version')
        body = body.replace(before, f'Version: {VERSION}\n'.encode())
        member.size = len(body)
        control[index] = member, body
    if sorted(edits) != sorted([INFO_LIBRARY, APP + 'Info.plist']):
        raise ValueError('required package members missing')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(pack_ar([
        ('debian-binary', parts['debian-binary']),
        ('control.tar.gz', tar_bytes(control)),
        ('data.tar.gz', tar_bytes(data)),
    ]))
    report = {
        'version': VERSION,
        'derived_from_package_sha256': sha(raw),
        'derived_from_library_sha256': LIBRARY_SHA256,
        'package_sha256': sha(output.read_bytes()),
        'patch_offset': PATCH_OFFSET,
        'instruction_before': OLD_INSTRUCTION.hex(),
        'instruction_after': NEW_INSTRUCTION.hex(),
        'changed_existing_files': edits,
        'on_device_diagnostic': 'index 1: scan 1 complete (12 rows), scan 2 complete (13 rows)',
        'release_published': False,
    }
    output.with_suffix('.manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(output)
    print('sha256', report['package_sha256'])
    return report


if __name__ == '__main__':
    build()
