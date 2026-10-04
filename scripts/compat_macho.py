"""Inspect deployment targets and port the pinned helper's existing whitelist.

Offsets below are exclusive to the SHA-pinned rh25.3 helper. The original
arm64e whitelist checks complete parent and helper paths under the same root.
Its equivalent is installed in the arm64 slice; all other native code stays.
"""
import hashlib
import struct

ARM64 = 0x100000C
HELPER_SHA = "878dab6af6d1b2a45d10c1e0e7fa5ca46eac2873eb7d723871a510bec55a00fb"

def fat_slices(data):
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("expected the pinned fat Mach-O helper")
    count = struct.unpack_from(">I", data, 4)[0]
    if count > 16:
        raise ValueError("unexpected slice count")
    slices = {}
    for index in range(count):
        cpu, subtype, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + 20 * index)
        if offset + size > len(data):
            raise ValueError("invalid slice bounds")
        slices[(cpu, subtype)] = data[offset:offset + size]
    return slices

def thin_arm64(data):
    if data[:4] == b"\xca\xfe\xba\xbe":
        data = fat_slices(data).get((ARM64, 0))
    if not data or data[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<II", data, 4) != (ARM64, 0):
        raise ValueError("missing regular arm64 slice for the preserved arm64 app")
    return data

def inspect(data):
    data = thin_arm64(data)
    count, size = struct.unpack_from("<II", data, 16)
    if 32 + size > len(data) or count > 1024:
        raise ValueError("invalid Mach-O commands")
    offset = 32
    result = {"architecture": "arm64", "minimum_ios": [], "loads": []}
    for _ in range(count):
        command, length = struct.unpack_from("<II", data, offset)
        if length < 8 or offset + length > 32 + size:
            raise ValueError("invalid load command")
        if command == 0x32:
            platform, minimum = struct.unpack_from("<II", data, offset + 8)
            if platform != 2:
                raise ValueError("not an iOS device binary")
            result["minimum_ios"].append(minimum)
        elif command == 0x25:
            result["minimum_ios"].append(struct.unpack_from("<I", data, offset + 8)[0])
        elif command in (0xC, 0x80000018, 0x8000001F, 0x80000023):
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            name = data[offset + name_offset:offset + length].split(b"\0")[0].decode()
            if not name.startswith(("/System/Library/", "/usr/lib/")):
                raise ValueError("bootstrap-specific linked dependency: " + name)
            result["loads"].append(name)
        offset += length
    if not result["minimum_ios"] or max(result["minimum_ios"]) > (15 << 16):
        raise ValueError("native binary requires a newer iOS than the candidate minimum")
    return result

def branch(at, target, instruction):
    distance = target - at
    if distance % 4 or not -(1 << 27) <= distance < (1 << 27):
        raise ValueError("invalid branch")
    return instruction | (distance // 4 & 0x3FFFFFF)

def compatible_aegis(data):
    if hashlib.sha256(data).hexdigest() != HELPER_SHA:
        raise ValueError("unknown helper; whitelist offsets cannot be applied")
    slices = fat_slices(data)
    result = bytearray(slices[(ARM64, 0)])
    # Verified arm64e code cave: 44 instructions followed by two exact suffixes.
    payload = bytearray(slices[(ARM64, 0x80000002)][0x7000:0x70FE])
    if payload[0xB0:] != b"/usr/libexec/harpy-reloaded/aegis/Applications/HarpyReloaded.app/HarpyReloaded":
        raise ValueError("unexpected parent whitelist")
    if any(result[0x7000:0x7000 + len(payload)]):
        raise ValueError("occupied arm64 cave")
    if result[0x7CF4:0x7D00] != bytes.fromhex("801300301f2003d5e1230091"):
        raise ValueError("unexpected arm64 parent validation site")
    # Regular arm64 has no PAC prologue/return. Keep the same stack/register ABI.
    struct.pack_into("<I", payload, 0, 0xD503201F)  # nop
    struct.pack_into("<I", payload, 0xAC, 0xD65F03C0)  # ret
    calls = [(0x10, 0x7EA8, 0x7E10), (0x1C, 0x7EE8, 0x7E40),
             (0x40, 0x7ED8, 0x7E34), (0x48, 0x7EB8, 0x7E1C),
             (0x54, 0x7EE8, 0x7E40), (0x74, 0x7ED8, 0x7E34),
             (0x8C, 0x7ED8, 0x7E34)]
    for location, original, target in calls:
        if struct.unpack_from("<I", payload, location)[0] != branch(0x7000 + location, original, 0x94000000):
            raise ValueError("unexpected whitelist call")
        struct.pack_into("<I", payload, location, branch(0x7000 + location, target, 0x94000000))
    result[0x7000:0x7000 + len(payload)] = payload
    site = struct.pack("<III", branch(0x7CF4, 0x7000, 0x94000000),
                       0x34000000 | ((0x7DA8 - 0x7CF8) // 4 << 5),
                       branch(0x7CFC, 0x7D3C, 0x14000000))
    result[0x7CF4:0x7D00] = site
    # The old optional libjailbreak bridge invokes both dlsym results unchecked.
    # A bootstrap can have the library while omitting those legacy exports.
    # Skip that optional bridge through its existing epilogue in that case.
    guard = 0x7120
    if any(result[guard:guard + 20]) or struct.unpack_from("<I", result, 0x7C84)[0] != branch(0x7C84, 0x7E10, 0x94000000):
        raise ValueError("unexpected optional jailbreak bridge")
    payload = struct.pack("<IIIII",
        0xB4000014 | ((0x7C9C - guard) // 4 << 5),  # cbz x20, old epilogue
        0xF94007E8,  # ldr x8, [sp, #8]: second dlsym result
        0xB4000008 | ((0x7C9C - guard - 8) // 4 << 5),
        branch(guard + 12, 0x7E10, 0x94000000),  # original getpid call
        branch(guard + 16, 0x7C88, 0x14000000))  # original first indirect call
    result[guard:guard + len(payload)] = payload
    struct.pack_into("<I", result, 0x7C84, branch(0x7C84, guard, 0x14000000))
    return bytes(result)
