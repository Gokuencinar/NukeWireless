"""Replace the pinned SplashView's image and use SwiftUI's existing black getter.

Image("iconImage", bundle: nil) is an inline Swift small string at 0x2ae1c.
Preserve its length, register usage and discriminator. Redirect only the color
call at 0x2ae10 to the Color.black getter already imported by this executable.
No catalog edits, hooks, new function ABI or timing changes are required.
"""
from pathlib import Path
import struct

IMAGE = b"NWBootPic"


def patch_name(binary, start, original, replacement):
    if len(original) != len(replacement) or len(original) > 15:
        raise ValueError("small-string length mismatch")
    result = bytearray(binary)
    words = 4 if len(original) >= 8 else (len(original) + 1) // 2
    # The first four MOVZ/MOVK instructions populate x0, remaining payload
    # instructions populate x1; the next instruction contains the discriminator.
    words += (max(0, len(original) - 8) + 1) // 2
    for index in range(words):
        position = start + index * 4
        word = struct.unpack_from("<I", binary, position)[0]
        register, shift = word & 31, (word >> 21) & 3
        expected_register = 0 if index < 4 else 1
        expected_shift = index if index < 4 else index - 4
        opcode = word & 0xff800000
        if register != expected_register or shift != expected_shift or opcode != (0xd2800000 if shift == 0 else 0xf2800000):
            raise ValueError(f"unexpected SplashView instruction at {position:#x}")
        before = int.from_bytes(original[index*2:index*2+2], "little")
        after = int.from_bytes(replacement[index*2:index*2+2], "little")
        if (word >> 5) & 0xffff != before:
            raise ValueError(f"unexpected SplashView resource at {position:#x}")
        struct.pack_into("<I", result, position, (word & ~(0xffff << 5)) | (after << 5))
    return bytes(result)


def patch_splash_resources(binary):
    # Both imported functions return SwiftUI.Color in x0. Color.black takes no
    # arguments, so the existing x0/x1/x2 name/bundle values are simply unused.
    # The original executable already imports and calls this getter at 0x17090.
    call = 0x2ae10
    old_target = 0x1150c8  # Color.init(_:bundle:)
    new_target = 0x11508c  # Color.black.getter
    before = 0x94000000 | ((old_target - call) // 4 & 0x3ffffff)
    after = 0x94000000 | ((new_target - call) // 4 & 0x3ffffff)
    if struct.unpack_from("<I", binary, call)[0] != before:
        raise ValueError("unexpected SplashView color call")
    result = bytearray(patch_name(binary, 0x2ae1c, b"iconImage", IMAGE))
    struct.pack_into("<I", result, call, after)
    return bytes(result)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    out = root / "build/audit"
    out.mkdir(parents=True, exist_ok=True)
    (out / "NWBootPic.png").write_bytes((root / "resources/startup/NukeWirelessIcon.png").read_bytes())
