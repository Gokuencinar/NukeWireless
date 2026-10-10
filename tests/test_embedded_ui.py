"""Verify fail-closed app dependencies and unchanged pinned native code."""
import argparse
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from embedded_ui import LOADS, embed_ui, dependencies, require_embedded_ui, load_commands


def fixture_executable():
    payload = b""
    for path in LOADS:
        name = path.encode() + b"\0"
        length = (24 + len(name) + 7) & ~7
        payload += struct.pack("<IIIIII", 0xC, length, 24, 0, 0x10000, 0x10000)
        payload += name.ljust(length - 24, b"\0")
    return struct.pack("<IIIIIIII", 0xFEEDFACF, 0x100000C, 0, 2, len(LOADS), len(payload), 0, 0) + payload


class LoaderTests(unittest.TestCase):
    def test_missing_weak_and_duplicate_ui_are_rejected(self):
        binary = fixture_executable()
        require_embedded_ui(binary)
        commands = load_commands(binary)
        for index in range(len(LOADS)):
            command, offset, length = commands[index]
            weak = bytearray(binary)
            struct.pack_into("<I", weak, offset, 0x80000018)
            with self.assertRaisesRegex(ValueError, "mandatory app dependency"):
                require_embedded_ui(weak)
            missing = bytearray(binary[:offset] + binary[offset + length:])
            struct.pack_into("<II", missing, 16, len(LOADS) - 1, len(missing) - 32)
            with self.assertRaisesRegex(ValueError, "mandatory app dependency"):
                require_embedded_ui(missing)
        duplicate = bytearray(binary + binary[32:32 + commands[0][2]])
        struct.pack_into("<II", duplicate, 16, len(LOADS) + 1, len(duplicate) - 32)
        with self.assertRaisesRegex(ValueError, "mandatory app dependency"):
            require_embedded_ui(duplicate)

    def test_unknown_binary_and_invalid_bounds_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown app"):
            embed_ui(fixture_executable())
        invalid = bytearray(fixture_executable())
        struct.pack_into("<I", invalid, 36, 0xFFFFFFF8)
        with self.assertRaisesRegex(ValueError, "invalid Mach-O command"):
            dependencies(invalid)


class PinnedAppTests(unittest.TestCase):
    def test_append_only_strong_dependencies_preserve_entire_native_body(self):
        from build_nuke_info_deb import APP, patch_visible_text, read_tar
        from startup_resources import patch_splash_resources
        from package_utils import read_ar, get_tar_member
        files = {m.name.removeprefix("./"): data for m, data in
                 read_tar(get_tar_member(read_ar(BASELINE.read_bytes()), "data.tar"))}
        before = patch_splash_resources(patch_visible_text(files[APP + "HarpyReloaded"]))
        after = embed_ui(before)
        require_embedded_ui(after)
        self.assertEqual(len(before), len(after))
        original_size = struct.unpack_from("<I", before, 20)[0]
        self.assertEqual(before[32:32 + original_size], after[32:32 + original_size])
        new_size = struct.unpack_from("<I", after, 20)[0]
        self.assertEqual(before[32 + new_size:], after[32 + new_size:])
        self.assertEqual(before[:16], after[:16])
        self.assertEqual(before[24:32], after[24:32])
        self.assertEqual(dependencies(after)[-2:], [(0xC, path) for path in LOADS])
        for location in (0xC5A8, 0x39610, 0x1152FC):
            self.assertEqual(before[location:location + 16], after[location:location + 16])
        with self.assertRaisesRegex(ValueError, "unknown app"):
            embed_ui(after)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path)
    args, rest = parser.parse_known_args()
    BASELINE = args.baseline
    PinnedAppTests.__unittest_skip__ = not bool(BASELINE)
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
