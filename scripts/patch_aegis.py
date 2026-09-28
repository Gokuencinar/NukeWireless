"""Patch Aegis's obsolete parent-path check for Nuke Wireless on randomized RootHide.

The new check compares the parent executable's entire physical path against
the expected app path under the helper's own randomized jailbreak root.
"""

from pathlib import Path
import io
import struct
import tarfile

from keystone import Ks, KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN
from package_utils import SOURCE, read_ar, get_tar_member


CAVE = 0x100007000
TEXT_BASE = 0x100000000
MAIN_CALL = 0x100007D74
SUCCESS = 0x100007E28
DENIAL = 0x100007DBC
STUBS = [
    0x100007EA8,  # getpid
    0x100007EE8,  # proc_pidpath
    0x100007ED8,  # memcmp
    0x100007EB8,  # getppid
    0x100007EE8,  # proc_pidpath
    0x100007ED8,  # memcmp
    0x100007ED8,  # memcmp
]
OUTPUT = Path(__file__).resolve().parents[1] / "build" / "aegis_roothide_patched"


def original_binary() -> bytes:
    parts = read_ar(SOURCE.read_bytes())
    with tarfile.open(fileobj=io.BytesIO(get_tar_member(parts, "data.tar")), mode="r:*") as tf:
        return tf.extractfile("./var/jb/usr/libexec/harpy-reloaded/aegis").read()


def fat_slice(data: bytes) -> tuple[int, int]:
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("unexpected fat Mach-O format")
    count = struct.unpack_from(">I", data, 4)[0]
    for i in range(count):
        cpu, sub, offset, size, align = struct.unpack_from(">IIIII", data, 8 + 20 * i)
        if cpu == 0x100000C and sub == 0x80000002:
            return offset, size
    raise ValueError("missing arm64e slice")


def source_to_keystone(source: str, pacibsp: int, retab: int) -> str:
    lines = []
    for line in source.splitlines():
        line = line.split("//", 1)[0].strip()
        if not line or line.startswith((".section", ".globl", ".p2align")):
            continue
        if line == "pacibsp":
            line = f".long 0x{pacibsp:08x}"
        elif line == "retab":
            line = f".long 0x{retab:08x}"
        elif line.startswith(".ascii "):
            literal = line.split('"', 2)[1].encode("ascii")
            line = ".byte " + ",".join(str(b) for b in literal)
        lines.append(line)
    return "\n".join(lines)


def encode_bl(at: int, target: int) -> int:
    delta = target - at
    assert delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27)
    return 0x94000000 | ((delta // 4) & 0x03FFFFFF)


def main() -> None:
    data = bytearray(original_binary())
    slice_offset, slice_size = fat_slice(data)
    main_offset = slice_offset + MAIN_CALL - TEXT_BASE
    cave_offset = slice_offset + CAVE - TEXT_BASE
    pacibsp = struct.unpack_from("<I", data, slice_offset + 0x7D44)[0]
    retab = struct.unpack_from("<I", data, slice_offset + 0x7E24)[0]
    asm_path = Path(__file__).resolve().parents[1] / "patches" / "aegis_parent_check.s"
    asm = source_to_keystone(asm_path.read_text(), pacibsp, retab)
    engine = Ks(KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN)
    encoded, count = engine.asm(asm, addr=CAVE)
    payload = bytearray(encoded)
    call_offsets = [i for i in range(0, len(payload) - 3, 4) if payload[i:i+4] == b"\0\0\0\x94"]
    if len(call_offsets) != len(STUBS):
        raise ValueError(f"expected {len(STUBS)} call placeholders; found {len(call_offsets)}")
    for offset, target in zip(call_offsets, STUBS):
        struct.pack_into("<I", payload, offset, encode_bl(CAVE + offset, target))
    if any(data[cave_offset:cave_offset+len(payload)]):
        raise ValueError("code cave is not empty")
    data[cave_offset:cave_offset+len(payload)] = payload

    site, _ = engine.asm(
        f"bl 0x{CAVE:x}; cbz w0, 0x{SUCCESS:x}; b 0x{DENIAL:x}", addr=MAIN_CALL
    )
    if len(site) != 12:
        raise ValueError("unexpected patch site length")
    data[main_offset:main_offset+12] = bytes(site)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(data)
    print("output", OUTPUT)
    print("arm64e slice", hex(slice_offset), hex(slice_size))
    print("cave bytes", len(payload), "at", hex(CAVE))
    print("site", bytes(site).hex())
    print("PAC/RET", hex(pacibsp), hex(retab))


if __name__ == "__main__":
    main()

