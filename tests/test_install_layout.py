"""Exercise the actual renamed Aegis whitelist in an ARM64 emulator.

Pass the SHA-pinned baseline and install unicorn==2.1.4 in the test environment.
No iOS processes, services or radio operations run in this test.
"""
import argparse
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from install_layout import APP, EXECUTABLE, HELPERS, APP_SUFFIX, AEGIS_SUFFIX, rename_path
from compat_macho import compatible_aegis
from build_nuke_info_deb import read_tar
from package_utils import get_tar_member, read_ar

BASELINE = None

class LayoutTests(unittest.TestCase):
    def test_baseline_paths_and_sidecars(self):
        for old, new in [("Applications/HarpyReloaded.app", APP.rstrip("/")),
                         ("Applications/HarpyReloaded.app/HarpyReloaded", APP+EXECUTABLE),
                         ("Applications/HarpyReloaded.app/HarpyReloaded.roothidepatch", APP+EXECUTABLE+".roothidepatch"),
                         ("usr/libexec/harpy-reloaded/aegis", HELPERS+"aegis"),
                         ("usr/libexec/harpy-reloaded", HELPERS.rstrip("/")),
                         ("usr/libexec/harpy-reloaded-other/aegis", "usr/libexec/harpy-reloaded-other/aegis")]:
            self.assertEqual(rename_path(old), new)

class WhitelistTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
        from unicorn import arm64_const as registers
        cls.Uc, cls.arch, cls.mode, cls.hook = Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
        cls.registers = registers
        contents = {m.name.removeprefix("./"): data for m,data in
                    read_tar(get_tar_member(read_ar(BASELINE.read_bytes()), "data.tar"))}
        cls.original = contents["usr/libexec/harpy-reloaded/aegis"]
        cls.binary = compatible_aegis(cls.original)

    def permitted(self, helper, parent):
        uc = self.Uc(self.arch, self.mode)
        r = self.registers
        base, stack, stop = 0x100000, 0x200000, 0x300000
        uc.mem_map(base, 0x10000)
        uc.mem_write(base, self.binary)
        uc.mem_map(stack, 0x20000)
        uc.mem_map(stop, 0x1000)
        uc.reg_write(r.UC_ARM64_REG_SP, stack+0x10000)
        uc.reg_write(r.UC_ARM64_REG_LR, stop)
        paths = {41: helper.encode(), 42: parent.encode()}
        def called(engine, address, size, context):
            offset = address-base
            if offset not in (0x7E10, 0x7E1C, 0x7E40, 0x7E34): return
            if offset == 0x7E10: result = 41
            elif offset == 0x7E1C: result = 42
            elif offset == 0x7E40:
                value = paths[engine.reg_read(r.UC_ARM64_REG_W0)]
                self.assertLess(len(value)+1, engine.reg_read(r.UC_ARM64_REG_W2))
                engine.mem_write(engine.reg_read(r.UC_ARM64_REG_X1), value+b"\0")
                result = len(value)
            else:
                count = engine.reg_read(r.UC_ARM64_REG_W2)
                first = bytes(engine.mem_read(engine.reg_read(r.UC_ARM64_REG_X0), count))
                second = bytes(engine.mem_read(engine.reg_read(r.UC_ARM64_REG_X1), count))
                result = 0 if first == second else 1
            engine.reg_write(r.UC_ARM64_REG_W0, result)
            engine.reg_write(r.UC_ARM64_REG_PC, engine.reg_read(r.UC_ARM64_REG_LR))
        uc.hook_add(self.hook, called)
        uc.emu_start(base+0x7000, stop, count=250)
        self.assertEqual(uc.reg_read(r.UC_ARM64_REG_PC), stop)
        self.assertEqual(uc.reg_read(r.UC_ARM64_REG_SP), stack+0x10000)
        return uc.reg_read(r.UC_ARM64_REG_W0) == 0

    def test_exact_same_root_is_required(self):
        for root in ["", "/var/jb", "/private/preboot/ABCD/jb", "/private/var/containers/Bundle/.jbroot-123"]:
            helper, parent = root+AEGIS_SUFFIX, root+APP_SUFFIX
            with self.subTest(root=root):
                self.assertTrue(self.permitted(helper, parent))
                self.assertFalse(self.permitted(helper, "/another-root"+parent))
                self.assertFalse(self.permitted(helper, parent+"-other"))
                self.assertFalse(self.permitted(helper+"-other", parent))
                self.assertFalse(self.permitted(helper, root+"/Applications/HarpyReloaded.app/HarpyReloaded"))
                self.assertFalse(self.permitted(root+"/usr/libexec/harpy-reloaded/aegis", parent))
        self.assertFalse(self.permitted("", ""))

    def test_changed_baseline_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown helper"):
            compatible_aegis(self.original+b"changed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path)
    args, rest = parser.parse_known_args()
    BASELINE = args.baseline
    WhitelistTests.__unittest_skip__ = not bool(BASELINE)
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
