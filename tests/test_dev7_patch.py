"""Check the exact package and binary delta for the private dev7 patch."""
import plistlib
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_dev7_patch as patch
from build_nuke_info_deb import APP, INFO_LIBRARY, read_tar
from package_utils import get_tar_member, read_ar


def members(path, kind):
    archive = read_ar(path.read_bytes())
    return {m.name.lstrip('./'): body for m, body in read_tar(get_tar_member(archive, kind))}


class Dev7PatchTests(unittest.TestCase):
    def test_exact_binary_change(self):
        old = members(patch.SOURCE, 'data.tar')[INFO_LIBRARY]
        new = members(patch.OUTPUT, 'data.tar')[INFO_LIBRARY]
        self.assertEqual(new, patch.patch_library(old))
        self.assertEqual(len(new), len(old))
        self.assertEqual(new[patch.PATCH_OFFSET:patch.PATCH_OFFSET + 4], patch.NEW_INSTRUCTION)
        self.assertIn(b'NWBuild-rh25.5-dev7', new)
        self.assertIn(patch.VERSION.encode(), new)
        self.assertNotIn(b'NWBuild-rh25.5-dev6', new)

    def test_only_library_and_version_metadata_change(self):
        old = members(patch.SOURCE, 'data.tar')
        new = members(patch.OUTPUT, 'data.tar')
        self.assertEqual(set(old), set(new))
        self.assertEqual({name for name in old if old[name] != new[name]},
                         {INFO_LIBRARY, APP + 'Info.plist'})
        info = plistlib.loads(new[APP + 'Info.plist'])
        self.assertEqual(info['CFBundleShortVersionString'], patch.VERSION)
        self.assertEqual(info['CFBundleDisplayName'], 'Nuke Wireless')
        self.assertEqual(members(patch.SOURCE, 'control.tar')['postinst'],
                         members(patch.OUTPUT, 'control.tar')['postinst'])
        self.assertIn(f'Version: {patch.VERSION}\n'.encode(),
                      members(patch.OUTPUT, 'control.tar')['control'])

    def test_rejects_other_binary(self):
        binary = members(patch.SOURCE, 'data.tar')[INFO_LIBRARY]
        with self.assertRaisesRegex(ValueError, 'unexpected dev6 library'):
            patch.patch_library(binary + b'x')


if __name__ == '__main__':
    unittest.main(verbosity=2)
