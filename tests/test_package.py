"""Inspect the produced package without installing or executing any contents."""
import io
import json
from pathlib import Path
import plistlib
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_nuke_info_deb as package
from package_utils import read_ar, get_tar_member
from build_manifest import sha, source_hashes
from language_catalog import native_strings

BASE = ROOT / 'dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb'
RESULT = ROOT / f'dist/com.gokuencinar.nukewireless_{package.VERSION}_iphoneos-arm64e.deb'

def members(path, kind):
    entries = package.read_tar(get_tar_member(read_ar(path.read_bytes()), kind))
    return {m.name.lstrip('./'): (m, data) for m,data in entries}

class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = members(BASE, 'data.tar')
        cls.after = members(RESULT, 'data.tar')

    def test_only_expected_existing_files_changed(self):
        allowed = {package.INFO_LIBRARY, package.APP+'Info.plist', package.APP+'HarpyReloaded'}
        changed = {n for n,(_,b) in self.before.items() if b != self.after[n][1]}
        self.assertEqual(changed, allowed)
        for name,(m,_) in self.before.items():
            new = self.after[name][0]
            self.assertEqual((m.mode,m.type,m.linkname),(new.mode,new.type,new.linkname),name)

    def test_app_only_length_preserving_text(self):
        old = self.before[package.APP+'HarpyReloaded'][1]
        new = self.after[package.APP+'HarpyReloaded'][1]
        self.assertEqual(new,package.patch_visible_text(old))
        self.assertEqual(len(new),len(old))
        self.assertEqual(old[0xc5a8:0xc5b8],new[0xc5a8:0xc5b8])
        for text in package.TEXT_EDITS: self.assertNotIn(text+b'\0',new)

    def test_metadata_resources_and_entitlements(self):
        info = plistlib.loads(self.after[package.APP+'Info.plist'][1])
        self.assertEqual(info['CFBundleIdentifier'],'me.midnightchips.harpy-reloaded')
        self.assertEqual(info['CFBundleDisplayName'],'NukeWireless')
        self.assertEqual(info['CFBundleShortVersionString'],package.VERSION)
        self.assertEqual(info['CFBundleLocalizations'],['en','es'])
        self.assertFalse(any('LocationUsage' in key for key in info))
        bundle = package.APP+'NukeWirelessResources.bundle/'
        vendors = plistlib.loads(self.after[bundle+'oui_vendors.plist'][1])
        self.assertTrue(self.after[bundle+'CreditsAvatar.png'][1].startswith(b'\x89PNG\r\n\x1a\n'))
        self.assertGreater(len(vendors),30000)
        self.assertTrue(all(re.fullmatch('[0-9A-F]{6}',k) and isinstance(v,str) and v for k,v in vendors.items()))
        languages = []
        for lang in ['en','es']:
            text = self.after[bundle+lang+'.lproj/Localizable.strings'][1].decode('utf8')
            keys = re.findall(r'^"([^"]+)" = ',text,re.M)
            self.assertEqual(len(keys),len(set(keys)))
            languages.append(set(keys))
        self.assertEqual(languages[0],languages[1])
        for lang in ['en','es']:
            native=self.after[bundle+lang+'.lproj/Native.strings'][1]
            self.assertEqual(native,native_strings(lang))
            self.assertEqual(self.after[package.APP+lang+'.lproj/Localizable.strings'][1],native)
        source = '\n'.join(p.read_text(encoding='utf8') for p in (ROOT/'src').glob('NW*.m'))
        self.assertTrue(set(re.findall(r'NWText\(@"([^"]+)"\)',source)) <= languages[0])
        acknowledgements = plistlib.loads(self.after[package.APP+'Acknowledgements.plist'][1])
        self.assertTrue(all('title' in row and 'license' in row for row in acknowledgements))

    def test_new_files_have_parent_directories_before_them(self):
        archive = package.read_tar(get_tar_member(read_ar(RESULT.read_bytes()), 'data.tar'))
        names = [m.name.lstrip('./').rstrip('/') for m, _ in archive]
        new = set(self.after) - set(self.before)
        for name in new:
            if self.after[name][0].isdir(): continue
            parent = str(Path(name).parent).replace('\\', '/')
            while parent and parent != '.':
                if parent in self.before:
                    self.assertTrue(self.before[parent][0].isdir(), parent)
                    break
                self.assertIn(parent, names, (name, parent))
                self.assertLess(names.index(parent), names.index(name), (name, parent))
                self.assertTrue(self.after[parent][0].isdir(), parent)
                parent = str(Path(parent).parent).replace('\\', '/')

    def test_control_and_signing(self):
        before = members(BASE,'control.tar'); after = members(RESULT,'control.tar')
        self.assertEqual(before['postinst'][1],after['postinst'][1])
        self.assertIn(b'ldid -S /usr/lib/TweakInject/NukeWirelessInfo.dylib',after['postinst'][1])
        self.assertIn(f'Version: {package.VERSION}\n'.encode(),after['control'][1])
        self.assertIn(b'firmware (>= 16.3)',after['control'][1])
        self.assertEqual(self.after[package.INFO_LIBRARY+'.roothidepatch'][0].linkname,'/usr/lib/DynamicPatches/AutoPatches.dylib')

    def test_provenance_and_no_location_requests(self):
        manifest=json.loads(RESULT.with_suffix('.manifest.json').read_text())
        self.assertEqual(manifest['extension']['sources'],source_hashes())
        binary=self.after[package.INFO_LIBRARY][1]
        self.assertEqual(sha(binary),manifest['extension']['binary_sha256'])
        self.assertIn(b'NWBuild-rh25.5-dev16',binary)
        self.assertNotIn(b'NWUIRegressionCheck',binary)
        for token in [b'CLLocationManager',b'requestWhenInUseAuthorization',b'requestAlwaysAuthorization']:
            self.assertNotIn(token,binary)

    def test_rejects_unknown_baseline_and_stale_binary(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp); (path/'wrong.deb').write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError,'baseline'):
                package.build(path/'wrong.deb',path,path/'output.deb')
            library = self.after[package.INFO_LIBRARY][1]
            (path/'NukeWirelessInfo_ios.dylib').write_bytes(library+b'changed')
            manifest=json.loads(RESULT.with_suffix('.manifest.json').read_text())['extension']
            (path/'build-manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError,'stale'):
                package.build(BASE,path,path/'output.deb')

if __name__ == '__main__': unittest.main(verbosity=2)
