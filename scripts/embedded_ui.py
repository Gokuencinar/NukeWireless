"""Make the current UI and network adapter mandatory app dependencies.

Only the SHA-pinned, already branded executable is accepted. Append load
commands inside its existing zero-filled header padding: no code, addresses,
section offsets, or existing dylib ordinals move. Re-sign after packaging.
"""
import hashlib
import struct

INPUT_SHA256 = "0736ed1876bcc97992b8379a32008010d2a510d7f1b413ecba96c2abe4fe0f7b"
LIBRARIES = ("NukeWirelessPaths.dylib", "NukeWirelessInfo.dylib")
LOADS = tuple("@executable_path/Frameworks/" + name for name in LIBRARIES)


def load_commands(binary):
    if len(binary) < 32 or struct.unpack_from("<III", binary) != (0xFEEDFACF, 0x100000C, 0):
        raise ValueError("expected regular arm64 Mach-O")
    count, size = struct.unpack_from("<II", binary, 16)
    if count > 1024 or 32 + size > len(binary):
        raise ValueError("invalid Mach-O command bounds")
    offset = 32
    result = []
    for _ in range(count):
        if offset + 8 > 32 + size:
            raise ValueError("invalid Mach-O command header")
        command, length = struct.unpack_from("<II", binary, offset)
        if length < 8 or length % 8 or offset + length > 32 + size:
            raise ValueError("invalid Mach-O command")
        result.append((command, offset, length))
        offset += length
    if offset != 32 + size:
        raise ValueError("inconsistent Mach-O command size")
    return result


def dependencies(binary):
    result = []
    for command, offset, length in load_commands(binary):
        if command in (0xC, 0x80000018, 0x8000001F, 0x80000023):
            start = struct.unpack_from("<I", binary, offset + 8)[0]
            if not 24 <= start < length:
                raise ValueError("invalid dylib command")
            name = binary[offset + start:offset + length].split(b"\0", 1)[0].decode("utf-8")
            result.append((command, name))
    return result


def require_embedded_ui(binary):
    imports = dependencies(binary)
    for name in LOADS:
        if [(command, path) for command, path in imports if path == name] != [(0xC, name)]:
            raise ValueError("UI must be a single mandatory app dependency: " + name)


def embed_ui(binary):
    if hashlib.sha256(binary).hexdigest() != INPUT_SHA256:
        raise ValueError("unknown app; cannot embed the current UI")
    commands = load_commands(binary)
    count, size = struct.unpack_from("<II", binary, 16)
    if (count, size) != (49, 6496) or struct.unpack_from("<I", binary, 12)[0] != 2:
        raise ValueError("unexpected pinned executable layout")
    payload = b""
    for name in LOADS:
        encoded = name.encode() + b"\0"
        length = (24 + len(encoded) + 7) & ~7
        payload += struct.pack("<IIIIII", 0xC, length, 24, 0, 0x10000, 0x10000)
        payload += encoded.ljust(length - 24, b"\0")
    start, end = 32 + size, 32 + size + len(payload)
    # First file-backed section is __text at 0x6a00 in this pinned executable.
    if end > 0x6A00 or any(binary[start:0x6A00]):
        raise ValueError("occupied executable header padding")
    result = bytearray(binary)
    struct.pack_into("<II", result, 16, count + len(LOADS), size + len(payload))
    result[start:end] = payload
    result = bytes(result)
    require_embedded_ui(result)
    if dependencies(result)[:-len(LOADS)] != dependencies(binary):
        raise ValueError("changed existing dependency ordinals")
    if load_commands(result)[:-len(LOADS)] != commands:
        raise ValueError("changed existing load commands")
    return result
