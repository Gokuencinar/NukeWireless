"""Test ownership migration and inspect real unified DEBs without running iOS code.

Pass --inputs and --output to verify a delivery. Linux also tests dpkg migration
inside a disposable root using harmless fixture scripts, never the iOS scripts.
"""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_unified_deb as unified
from package_utils import directory, pack_ar, regular, tar_bytes

INPUTS = OUTPUT = None
BASH = shutil.which("bash") if os.name != "nt" else next(
    (str(p) for p in [Path("C:/Program Files/Git/bin/bash.exe")] if p.exists()), None)


def fixture(folder, scheme, worker):
    prefix, inject, architecture, _ = unified.SCHEMES[scheme]
    package = unified.WORKER_PACKAGE if worker else unified.PACKAGE
    version = unified.WORKER_VERSION if worker else unified.APP_VERSION
    path = folder / f"{package}_{version}_{architecture}.deb"
    control = (f"Package: {package}\nName: Fixture\nVersion: {version}\nArchitecture: {architecture}\n"
               "Maintainer: Test <test@example.invalid>\nDepends: firmware (>= 15.0), firmware (<< 19.0), ldid\nDescription: Fixture\n").encode()
    script = b"#!/bin/sh\nset -e\nprintf '" + (b"worker" if worker else b"app") + b"\\n' >> \"$NW_TEST_LOG\"\nexit 0\n"
    controls = [regular("control", control), regular("postinst", script, 0o755)]
    if worker:
        files = {prefix + "usr/bin/nwbt-run": b"runner", prefix + "usr/bin/nwbt-inspect": b"inspector",
                 prefix + "usr/lib/NukeBluetoothBridge.dylib": b"bridge",
                 prefix + "usr/share/nukewireless-bluetooth/README.txt":
                     f"Remove with dpkg -r {unified.WORKER_PACKAGE}.\n".encode()}
        report = {"sources": unified.bluetooth_sources(),
                  "files": {PurePosixPath(n).name: unified.sha(b) for n, b in files.items() if not n.endswith(".txt")}}
    else:
        files = {prefix + inject + "/NukeWirelessInfo.dylib": b"extension",
                 prefix + "usr/share/nukewireless-roothide/compatibility.json":
                     json.dumps({"minimum_ios":"15.0", "maximum_ios_exclusive":"19.0", "runtime_verified":False}).encode(),
                 prefix + inject + "/NukeWirelessPaths.dylib": b"adapter",
                 prefix + "usr/libexec/harpy-reloaded/nw-hotspot": b"hotspot",
                 prefix + unified.APP + "Info.plist": plistlib.dumps({
                     "CFBundleIdentifier": "me.midnightchips.harpy-reloaded", "CFBundleShortVersionString": version, "MinimumOSVersion":"15.0",
                     "NukeWirelessPackageScheme": scheme, "NukeWirelessWorkerVersion": unified.WORKER_VERSION})}
        controls.append(regular("prerm", b"#!/bin/sh\nexit 0\n", 0o755))
        report = {"core": {"sources": unified.source_hashes(), "binary_sha256": unified.sha(b"extension"),
                           "hotspot_helper_sha256": unified.sha(b"hotspot"), "source_commit": "fixture"},
                  "adapter": {"sources": unified.compat_sources(), "path_library_sha256": unified.sha(b"adapter")}}
    entries = unified.ordered_entries([regular(n, b, 0o755) for n, b in files.items()])
    # Reproduce the old app archive's root directory after bootstrap prefixing.
    # Bypass ordered_entries here intentionally: the unified builder must fix it.
    if not worker:
        entries.append(directory(prefix + "."))
    path.write_bytes(pack_ar([("debian-binary", b"2.0\n"), ("control.tar.gz", tar_bytes(controls)),
                             ("data.tar.gz", tar_bytes(entries))]))
    report.update(package_sha256=unified.sha(path.read_bytes()), scheme=scheme, architecture=architecture, version=version)
    path.with_suffix(".manifest.json").write_text(json.dumps(report), encoding="utf-8")
    return path


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nuke-unified-test-")
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_archive_paths_are_canonical_and_traversal_is_rejected(self):
        entries = unified.ordered_entries([
            directory("."), directory("var/jb/."), directory("var/jb"),
            regular("var//jb/./usr/bin/tool", b"tool")])
        names = [m.name for m, _ in entries]
        self.assertEqual(len(names), len(set(names)))
        self.assertNotIn("./.", names)
        self.assertNotIn("./var/jb/.", names)
        self.assertIn("./var/jb/usr/bin/tool", names)
        with self.assertRaisesRegex(ValueError, "unsafe package path"):
            unified.ordered_entries([regular("var/jb/../escape", b"bad")])
        with self.assertRaisesRegex(ValueError, "duplicate package file"):
            unified.ordered_entries([regular("a/./b", b"one"), regular("a/b", b"two")])

    def test_installer_removes_only_firmware_limits(self):
        for scheme in unified.SCHEMES:
            with self.subTest(scheme=scheme):
                app, worker = fixture(self.folder, scheme, False), fixture(self.folder, scheme, True)
                output = self.folder/(scheme+".deb")
                unified.build(app, worker, output, scheme)
                control = unified.fields(unified.members(output.read_bytes(), "control.tar")["control"][1])
                self.assertEqual(control["Depends"], "ldid")
                prefix = unified.SCHEMES[scheme][0]
                files = unified.members(output.read_bytes(), "data.tar")
                self.assertNotIn("MinimumOSVersion", plistlib.loads(files[prefix+unified.APP+"Info.plist"][1]))
                report = json.loads(output.with_suffix('.manifest.json').read_text(encoding='utf-8'))
                self.assertIsNone(report["installation_policy"]["maximum_ios_exclusive"])
                self.assertIsNone(report["installation_policy"]["minimum_ios"])
                self.assertEqual(report["installation_policy"]["binary_minimum_ios"],"15.0")
                self.assertFalse(report["native_payload_changed"])

    @unittest.skipUnless(shutil.which("dpkg") and os.geteuid() == 0 if os.name != "nt" else False,
                         "requires Linux dpkg as root")
    def test_install_without_firmware_provider_or_ignoring_dependencies(self):
        app, worker = fixture(self.folder, "rootful", False), fixture(self.folder, "rootful", True)
        combined = self.folder/"unified.deb"
        unified.build(app, worker, combined, "rootful")
        root = self.folder/"no-firmware-provider"
        (root/"var/lib/dpkg").mkdir(parents=True)
        (root/"var/lib/dpkg/status").touch()
        dependencies = []
        for name, version in [("ldid","1.0")]:
            path = self.folder/(name+".deb")
            control = f"Package: {name}\nVersion: {version}\nArchitecture: iphoneos-arm\nMaintainer: Test <test@example.invalid>\nDescription: Fixture\n".encode()
            path.write_bytes(pack_ar([("debian-binary",b"2.0\n"),
                                      ("control.tar.gz",tar_bytes([regular("control",control)])),
                                      ("data.tar.gz",tar_bytes([]))]))
            dependencies.append(str(path))
        command = ["dpkg","--root="+str(root),"--force-script-chrootless","--force-architecture","--install"]
        env = dict(os.environ,NW_TEST_LOG=str(root/"script-log"))
        result = subprocess.run(command+dependencies+[str(combined)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_reject_wrong_bootstrap_and_stale_source(self):
        app, worker = fixture(self.folder, "rootful", False), fixture(self.folder, "rootless", True)
        with self.assertRaisesRegex(ValueError, "bootstrap mismatch"):
            unified.build(app, worker, self.folder / "reject.deb", "rootful")
        worker = fixture(self.folder, "rootful", True)
        manifest = worker.with_suffix(".manifest.json")
        report = json.loads(manifest.read_text(encoding="utf-8"))
        report["sources"]["src/NWDeviceCatalog.h"] = "stale"
        manifest.write_text(json.dumps(report), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "stale Bluetooth"):
            unified.build(app, worker, self.folder / "reject.deb", "rootful")

    def test_reject_modified_package(self):
        app, worker = fixture(self.folder, "rootful", False), fixture(self.folder, "rootful", True)
        worker.write_bytes(worker.read_bytes() + b"tampered")
        with self.assertRaisesRegex(ValueError, "package hash"):
            unified.build(app, worker, self.folder / "reject.deb", "rootful")

    @unittest.skipUnless(BASH, "shell unavailable")
    def test_postinst_runs_both_and_propagates_failure(self):
        log, script = self.folder / "log.txt", self.folder / "postinst"
        good = b"#!/bin/sh\nset -e\nprintf 'ok\\n' >> \"$NW_TEST_LOG\"\nexit 0\n"
        bad = b"#!/bin/sh\nset -e\nfalse\nexit 0\n"
        env = dict(os.environ, NW_TEST_LOG=log.as_posix())
        for app, worker, expected_status, expected_lines in [
            (good, good, 0, ["ok", "ok"]), (good, bad, 1, []), (bad, good, 1, ["ok"])]:
            log.write_text("", encoding="utf-8")
            script.write_bytes(unified.combined_postinst(app, worker))
            result = subprocess.run([BASH, script.as_posix()], env=env, capture_output=True)
            self.assertEqual(result.returncode, expected_status, result.stderr)
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), expected_lines)

    @unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("dpkg") and os.geteuid() == 0,
                         "dpkg migration requires isolated Linux CI as root")
    def test_dpkg_fresh_install_upgrade_ownership_and_removal(self):
        for scheme, (prefix, _, architecture, _) in unified.SCHEMES.items():
          app, worker = fixture(self.folder, scheme, False), fixture(self.folder, scheme, True)
          combined = self.folder / (scheme + ".deb")
          unified.build(app, worker, combined, scheme)
          for upgrade in (False, True):
            root = self.folder / (scheme + ("-upgrade" if upgrade else "-fresh"))
            (root / "var/lib/dpkg").mkdir(parents=True)
            (root / "var/lib/dpkg/status").touch()
            bootstrap = root / "var/jb/keep-bootstrap"
            bootstrap.parent.mkdir(parents=True, exist_ok=True)
            bootstrap.write_text("untouched", encoding="utf-8")
            log = root / "script-log"
            env = dict(os.environ, NW_TEST_LOG=str(log))
            def dpkg(*args):
                result = subprocess.run(["dpkg", "--root=" + str(root), "--force-script-chrootless",
                                         "--force-architecture", "--force-depends", *args],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            if upgrade:
                dpkg("--install", str(worker), str(app))
            log.write_text("", encoding="utf-8")
            dpkg("--install", str(combined))
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), ["worker", "app"])
            query = subprocess.check_output(["dpkg-query", "--admindir=" + str(root / "var/lib/dpkg"),
                                             "--show", "--showformat=${Version} ${Status}", unified.PACKAGE], text=True)
            self.assertEqual(query, unified.VERSION + " install ok installed")
            owner = subprocess.check_output(["dpkg-query", "--admindir=" + str(root / "var/lib/dpkg"),
                                             "--search", "/" + prefix + "usr/bin/nwbt-run"], text=True)
            owner_id, separator, owned_path = owner.strip().rpartition(": ")
            self.assertEqual((separator, owned_path), (": ", "/" + prefix + "usr/bin/nwbt-run"))
            self.assertIn(owner_id, {unified.PACKAGE, unified.PACKAGE + ":" + architecture})
            dpkg("--remove", unified.PACKAGE)
            self.assertFalse((root / prefix / "usr/bin/nwbt-run").exists())
            self.assertFalse((root / prefix / unified.APP / "Info.plist").exists())
            self.assertEqual(bootstrap.read_text(encoding="utf-8"), "untouched")

    @unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("dpkg") and os.geteuid() == 0,
                         "dpkg recovery requires isolated Linux CI as root")
    def test_old_rootless_failure_and_targeted_record_repair(self):
        app, worker = fixture(self.folder, "rootless", False), fixture(self.folder, "rootless", True)
        combined = self.folder / "legacy.deb"
        unified.build(app, worker, combined, "rootless")
        raw = combined.read_bytes()
        controls = unified.members(raw, "control.tar")
        control = unified.fields(controls["control"][1])
        control["Version"] = "2.0.0~diagnostic5+bundle1"
        controls["control"] = regular("control", ("\n".join(f"{k}: {v}" for k, v in control.items())+"\n").encode())
        entries = list(unified.members(raw, "data.tar").values()) + [directory("var/jb/.")]
        combined.write_bytes(pack_ar([("debian-binary", b"2.0\n"),
                                     ("control.tar.gz", tar_bytes(list(controls.values()))),
                                     ("data.tar.gz", tar_bytes(entries))]))
        root = self.folder / "broken-rootless"
        admin = root / "var/lib/dpkg"
        admin.mkdir(parents=True)
        (admin / "status").touch()
        sentinel = root / "var/jb/keep-bootstrap"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text("untouched", encoding="utf-8")
        env = dict(os.environ, NW_TEST_LOG=str(root / "script-log"))
        command = ["dpkg", "--root="+str(root), "--force-script-chrootless",
                   "--force-architecture", "--force-depends"]
        result = subprocess.run(command+["--install", str(combined)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        result = subprocess.run(command+["--remove", unified.PACKAGE], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn("Invalid argument", result.stderr)
        self.assertIn("/var/jb/.", result.stderr)
        record, = list((admin / "info").glob(unified.PACKAGE+"*.list"))
        before = record.read_bytes()
        self.assertIn(b"/var/jb/.\n", before)
        # Match the reported bootstrap: only the already available tools, no awk.
        minimal_bin = self.folder / "recovery-tools"
        minimal_bin.mkdir()
        for tool in ["id", "dpkg-query", "grep", "mktemp", "cp", "mv", "rm"]:
            executable = shutil.which(tool)
            self.assertIsNotNone(executable, tool)
            (minimal_bin / tool).symlink_to(executable)
        recovery_env = dict(os.environ, PATH=str(minimal_bin))
        self.assertIsNone(shutil.which("awk", path=recovery_env["PATH"]))
        repair = [shutil.which("sh"), str(ROOT / "scripts/repair_rootless_package_list.sh"), str(admin)]
        result = subprocess.run(repair, env=recovery_env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(record.read_bytes(), b"".join(line for line in before.splitlines(keepends=True)
                                                     if line != b"/var/jb/.\n"))
        backup, = list((admin / "info").glob(record.name+".nw-backup.*"))
        self.assertEqual(backup.read_bytes(), before)
        # A second invocation must leave the already repaired database alone.
        result = subprocess.run(repair, env=recovery_env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        result = subprocess.run(command+["--remove", unified.PACKAGE], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "untouched")


class DeliveryTests(unittest.TestCase):
    def test_real_payload_scripts_and_provenance(self):
        for scheme, (prefix, _, architecture, _) in unified.SCHEMES.items():
            with self.subTest(scheme=scheme):
                app_path = INPUTS / f"{unified.PACKAGE}_{unified.APP_VERSION}_{architecture}.deb"
                worker_path = INPUTS / f"{unified.WORKER_PACKAGE}_{unified.WORKER_VERSION}_{architecture}.deb"
                path = OUTPUT / f"{unified.PACKAGE}_{unified.VERSION}_{architecture}.deb"
                app = unified.load_package(app_path, scheme)
                worker = unified.load_package(worker_path, scheme, True)
                raw = path.read_bytes()
                files, scripts = unified.members(raw, "data.tar"), unified.members(raw, "control.tar")
                report = json.loads(path.with_suffix(".manifest.json").read_text(encoding="utf-8"))
                self.assertEqual(report["package_sha256"], unified.sha(raw))
                self.assertEqual(report["inputs"], {"app": unified.sha(app[0]), "bluetooth": unified.sha(worker[0])})
                self.assertFalse(report["native_payload_changed"])
                self.assertFalse(report["unified_installation_verified"])
                self.assertEqual(report["components"], {"app": app[1], "bluetooth": worker[1]})
                self.assertEqual(set(report["changed_payload_files"]), {
                    prefix+"usr/share/nukewireless-bluetooth/README.txt",
                    prefix+unified.APP+"Info.plist",
                    prefix+"usr/share/nukewireless-roothide/compatibility.json"})
                for original in (app[2], worker[2]):
                    for name, (member, data) in original.items():
                        name = PurePosixPath(name).as_posix()
                        if name == ".":
                            self.assertTrue(member.isdir())
                            continue
                        actual, content = files[name]
                        self.assertEqual((actual.mode, actual.uid, actual.gid, actual.type, actual.linkname),
                                         (member.mode, member.uid, member.gid, member.type, member.linkname), name)
                        if name not in report["changed_payload_files"]:
                            self.assertEqual(content, data, name)
                self.assertEqual(scripts["prerm"][1], app[3]["prerm"][1])
                postinst = scripts["postinst"][1]
                self.assertEqual(postinst.count(app[3]["postinst"][1]), 1)
                self.assertEqual(postinst.count(worker[3]["postinst"][1]), 1)
                control = unified.fields(scripts["control"][1])
                self.assertEqual(control["Version"], unified.VERSION)
                self.assertNotIn("firmware",control["Depends"])
                metadata = plistlib.loads(files[prefix+unified.APP+"Info.plist"][1])
                self.assertNotIn("MinimumOSVersion",metadata)
                original_metadata = plistlib.loads(app[2][prefix+unified.APP+"Info.plist"][1])
                original_metadata.pop("MinimumOSVersion")
                self.assertEqual(metadata,original_metadata)
                status_path = prefix+"usr/share/nukewireless-roothide/compatibility.json"
                status = json.loads(files[status_path][1])
                original_status = json.loads(app[2][status_path][1])
                original_status.update(maximum_ios_exclusive=None, installation_policy=unified.INSTALLATION_POLICY)
                self.assertEqual(status, original_status)
                self.assertEqual(report["installation_policy"],unified.INSTALLATION_POLICY)
                self.assertIn(unified.WORKER_PACKAGE, control["Conflicts"].split(", "))
                self.assertIn(unified.WORKER_PACKAGE, control["Replaces"].split(", "))
                self.assertEqual(control["Provides"], f"{unified.WORKER_PACKAGE} (= {unified.WORKER_VERSION})")
                for old in (app[4], worker[4]):
                    for field in ("Depends", "Pre-Depends"):
                        for dependency in old.get(field, "").split(", "):
                            if dependency and dependency not in {"firmware (>= 15.0)","firmware (<< 19.0)"}:
                                self.assertIn(dependency, control[field].split(", "))
                seen = set()
                for member, _ in unified.read_tar(unified.get_tar_member(unified.read_ar(raw), "data.tar")):
                    name = member.name.removeprefix("./").rstrip("/")
                    self.assertEqual(name, PurePosixPath(name).as_posix())
                    self.assertNotEqual(name, ".")
                    self.assertNotIn("..", name.split("/"))
                    self.assertNotIn(name, seen)
                    for parent in PurePosixPath(name).parents:
                        if parent.as_posix() != ".":
                            self.assertIn(parent.as_posix(), seen)
                    seen.add(name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--output", type=Path)
    args, remainder = parser.parse_known_args()
    if bool(args.inputs) != bool(args.output):
        parser.error("--inputs and --output must be supplied together")
    INPUTS, OUTPUT = args.inputs, args.output
    DeliveryTests.__unittest_skip__ = not bool(INPUTS)
    unittest.main(argv=[sys.argv[0], *remainder], verbosity=2)
