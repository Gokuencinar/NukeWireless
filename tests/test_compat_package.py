"""Check scheme separation and provenance without running package scripts.

python tests/test_compat_package.py --artifact /path/to/fresh/artifact
The artifact contains audit/ and bluetooth/ from the compatibility workflow.
"""
import argparse
import json
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_manifest import sha, source_hashes
import build_compat_debs as app
import build_bluetooth_deb as bluetooth
from compat_layout import SCHEMES, ordered_entries
from compat_manifest import compat_sources
from compat_macho import inspect
from package_utils import get_tar_member, read_ar, regular, directory

ARTIFACT = None
BASELINE = ROOT / 'dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb'


def contents(path, archive):
    return {member.name.removeprefix('./').rstrip('/'): (member, data)
            for member, data in app.read_tar(get_tar_member(read_ar(path.read_bytes()), archive))}


class LayoutTests(unittest.TestCase):
    def test_reject_collisions_and_parent_traversal(self):
        for entries in ([regular('usr/item', b'a'), regular('usr/item', b'b')],
                        [regular('usr/item', b'a'), directory('usr/item')],
                        [regular('usr/item', b'a'), regular('usr/item/child', b'b')],
                        [regular('usr/../outside', b'a')]):
            with self.assertRaises(ValueError):
                ordered_entries(entries)

    def test_construct_missing_ancestors(self):
        entries = ordered_entries([regular('var/jb/Applications/App.app/file', b'a')])
        names = [member.name.removeprefix('./').rstrip('/') for member, _ in entries]
        self.assertEqual(names, ['var', 'var/jb', 'var/jb/Applications',
                                 'var/jb/Applications/App.app', 'var/jb/Applications/App.app/file'])


@unittest.skipUnless(ARTIFACT, 'pass --artifact to inspect the actual compiled candidates')
class CandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nuke-compat-test-')
        cls.folder = Path(cls.temp.name)
        cls.core = cls.folder / 'core.deb'
        app.build(BASELINE, ARTIFACT / 'audit', cls.core)
        cls.apps, cls.workers = {}, {}
        for scheme, (_, _, architecture, _) in SCHEMES.items():
            app.package(scheme, cls.core.read_bytes(), ARTIFACT / 'audit', cls.folder)
            cls.apps[scheme] = cls.folder / f'com.gokuencinar.nukewireless_{app.VERSION}_{architecture}.deb'
            cls.workers[scheme] = cls.folder / f'worker-{scheme}.deb'
            bluetooth.build(ARTIFACT / 'bluetooth', cls.workers[scheme], scheme)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_bootstrap_paths_dependencies_and_identity(self):
        for scheme, (prefix, inject, architecture, _) in SCHEMES.items():
            with self.subTest(scheme=scheme):
                files = contents(self.apps[scheme], 'data.tar')
                controls = contents(self.apps[scheme], 'control.tar')
                control = controls['control'][1].decode('utf-8')
                script = controls['postinst'][1].decode('utf-8')
                self.assertIn(f'Architecture: {architecture}\n', control)
                self.assertEqual('rootless-compat' in control, scheme == 'roothide')
                self.assertIn('firmware (>= 15.0), firmware (<< 19.0)', control)
                info = plistlib.loads(files[prefix + app.APP + 'Info.plist'][1])
                self.assertEqual(info['CFBundleIdentifier'], 'me.midnightchips.harpy-reloaded')
                self.assertEqual((info['MinimumOSVersion'], info['CFBundleVersion']), ('15.0', '20006'))
                self.assertEqual(info['CFBundleShortVersionString'], app.VERSION)
                self.assertEqual(info['NukeWirelessPackageScheme'], scheme)
                self.assertEqual(info['CFBundleDisplayName'], 'NukeWireless Dev')
                self.assertTrue(info['UIFileSharingEnabled'])
                self.assertTrue(info['LSSupportsOpeningDocumentsInPlace'])
                self.assertEqual(info['NukeWirelessWorkerVersion'], bluetooth.VERSION)
                self.assertIn('-Ime.midnightchips.harpy-reloaded "-S$ENT" "$APP"', script)
                self.assertIn('ldid -S /' + prefix + inject + '/NukeWirelessInfo.dylib', script)
                self.assertIn('chmod 4755 "$BASE/nw-hotspot"', script)
                helper = files[prefix + 'usr/libexec/harpy-reloaded/nw-hotspot'][1]
                self.assertEqual(sha(helper), json.loads(self.apps[scheme].with_suffix('.manifest.json').read_text(encoding='utf-8'))['core']['hotspot_helper_sha256'])
                self.assertIn((prefix + 'usr/libexec/harpy-reloaded/nw-hotspot clear').encode(), controls['prerm'][1])
                self.assertEqual(any(name.endswith('.roothidepatch') for name in files), scheme == 'roothide')
                self.assertFalse(any('HarpyRootHidePaths' in name for name in files))
                self.assertIn(prefix + inject + '/NukeWirelessPaths.dylib', files)
                self.assertFalse(any(name.startswith('var/jb/') for name in files) if not prefix else
                                 any(name.startswith(('Applications/', 'usr/')) for name in files))

    def test_current_ui_resources_and_source_manifest(self):
        for scheme, (prefix, inject, _, _) in SCHEMES.items():
            with self.subTest(scheme=scheme):
                files = contents(self.apps[scheme], 'data.tar')
                report = json.loads(self.apps[scheme].with_suffix('.manifest.json').read_text(encoding='utf-8'))
                self.assertEqual(report['package_sha256'], sha(self.apps[scheme].read_bytes()))
                self.assertEqual(report['core']['sources'], source_hashes())
                self.assertEqual(report['adapter']['sources'], compat_sources())
                self.assertEqual(report['core']['binary_sha256'], sha(files[prefix + inject + '/NukeWirelessInfo.dylib'][1]))
                self.assertFalse(report['runtime_verified'])
                self.assertIn('src/NWMainTabs.m', report['core']['sources'])
                self.assertIn('src/NWBluetoothCatalog.m', report['core']['sources'])
                self.assertIn(b'NWBuild-diagnostic6', files[prefix + inject + '/NukeWirelessInfo.dylib'][1])
                bundle = prefix + app.APP + 'NukeWirelessResources.bundle/'
                for brand in ['apple', 'google', 'microsoft', 'samsung', 'android']:
                    self.assertEqual(files[bundle + 'brands/' + brand + '.pdf'][1],
                                     (ROOT / 'resources/brands' / (brand + '.pdf')).read_bytes())

    def test_all_native_files_really_target_ios15(self):
        for path in [*self.apps.values(), *self.workers.values()]:
            files = contents(path, 'data.tar')
            for name, (member, data) in files.items():
                if member.isfile() and data[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                    with self.subTest(package=path.name, binary=name):
                        report = bluetooth.inspect_tool(data) if name.endswith(('nwbt-run', 'nwbt-inspect')) else inspect(data)
                        self.assertLessEqual(max(report['minimum_ios']), 15 << 16)

    def test_worker_same_payload_guard_and_scheme_signing(self):
        for scheme, (prefix, _, architecture, _) in SCHEMES.items():
            with self.subTest(scheme=scheme):
                files = contents(self.workers[scheme], 'data.tar')
                controls = contents(self.workers[scheme], 'control.tar')
                script = controls['postinst'][1].decode('utf-8')
                self.assertIn(f'Architecture: {architecture}\n'.encode(), controls['control'][1])
                self.assertEqual(b'rootless-compat' in controls['control'][1], scheme == 'roothide')
                for name, relative in [('nwbt-run', 'usr/bin/'), ('nwbt-inspect', 'usr/bin/'),
                                       ('NukeBluetoothBridge.dylib', 'usr/lib/')]:
                    self.assertEqual(files[prefix + relative + name][1], (ARTIFACT / 'bluetooth' / name).read_bytes())
                self.assertIn(f'chmod 4755 /{prefix}usr/bin/nwbt-run', script)
                report = json.loads(files[prefix + 'usr/share/nukewireless-bluetooth/build-manifest.json'][1])
                self.assertEqual(report['native_admission_policy'], 'skywalk-runtime-contract-v1')
                self.assertEqual(report['legacy_runtime_allowlist'], [{'machine': 'iPhone11,2', 'ios': '16.3.1'}])
                self.assertEqual(report['verified_bootstrap'], 'roothide')
                self.assertFalse(report['runtime_verified'])

    def test_parents_before_children_and_no_duplicates(self):
        for path in [*self.apps.values(), *self.workers.values()]:
            entries = app.read_tar(get_tar_member(read_ar(path.read_bytes()), 'data.tar'))
            seen = set()
            for member, _ in entries:
                name = member.name.removeprefix('./').rstrip('/')
                self.assertNotIn(name, seen, path.name)
                for parent in PurePosixPath(name).parents:
                    if parent.as_posix() != '.':
                        self.assertIn(parent.as_posix(), seen, (path.name, name))
                seen.add(name)

    def test_reject_stale_adapter_and_newer_macho(self):
        audit = self.folder / 'stale'
        audit.mkdir()
        for name in ['compat-manifest.json', 'build-manifest.json']:
            (audit / name).write_bytes((ARTIFACT / 'audit' / name).read_bytes())
        (audit / 'NukeWirelessPaths_ios.dylib').write_bytes(b'not current')
        with self.assertRaisesRegex(ValueError, 'mismatched compatibility'):
            app.package('rootless', self.core.read_bytes(), audit, self.folder / 'rejected')
        import struct
        binary = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, 6, 1, 24, 0, 0)
        binary += struct.pack('<IIIIII', 0x32, 24, 2, 16 << 16, 0, 0)
        with self.assertRaisesRegex(ValueError, 'newer iOS'):
            inspect(binary)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact', type=Path)
    args, remainder = parser.parse_known_args()
    ARTIFACT = args.artifact
    # unittest skip decorators are evaluated at import time.
    CandidateTests.__unittest_skip__ = not bool(ARTIFACT)
    unittest.main(argv=[sys.argv[0], *remainder], verbosity=2)
