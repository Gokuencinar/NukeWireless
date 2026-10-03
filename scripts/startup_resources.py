"""Replace only the pinned SplashView's resource names and add its own color.

SplashView's body at 0x2adf0 builds Color("AccentColor", bundle: nil),
then at 0x2ae1c builds Image("iconImage", bundle: nil). These are inline
Swift small strings, not C strings. Preserve their length, register usage,
discriminator, function calls and every other instruction.

The original BOM catalog has single-leaf FACETKEYS and RENDITIONS trees.
Clone its named-color rendition under a fresh identifier, retaining every
original catalog key/value. No original AccentColor or image is replaced.
"""
import io
from pathlib import Path
import struct
import tarfile

from package_utils import get_tar_member, read_ar

APP = "Applications/HarpyReloaded.app/"
COLOR = b"NWBootColor"
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


def patch_splash_names(binary):
    return patch_name(patch_name(binary, 0x2adf0, b"AccentColor", COLOR),
                      0x2ae1c, b"iconImage", IMAGE)


def add_startup_color(catalog):
    if catalog[:8] != b"BOMStore":
        raise ValueError("not a BOM catalog")
    index_offset, _, variables_offset, _ = struct.unpack_from(">4I", catalog, 16)
    count = struct.unpack_from(">I", catalog, index_offset)[0]
    locations = [struct.unpack_from(">II", catalog, index_offset + 4 + i*8) for i in range(count)]
    blocks = [catalog[p:p+n] for p, n in locations]
    variables = {}
    cursor = variables_offset + 4
    for _ in range(struct.unpack_from(">I", catalog, variables_offset)[0]):
        block, length = struct.unpack_from(">IB", catalog, cursor)
        cursor += 5
        variables[catalog[cursor:cursor+length]] = block
        cursor += length

    def leaf(name):
        root = blocks[variables[name]]
        if root[:4] != b"tree":
            raise ValueError("unexpected catalog tree")
        index = struct.unpack_from(">I", root, 8)[0]
        node = blocks[index]
        flag, entries, forward, backward = struct.unpack_from(">HHII", node)
        if (flag, forward, backward) != (1, 0, 0):
            raise ValueError("only the pinned single-leaf catalog is supported")
        return index, [struct.unpack_from(">II", node, 12 + i*8) for i in range(entries)]

    facet_index, facets = leaf(b"FACETKEYS")
    rendition_index, renditions = leaf(b"RENDITIONS")
    old_facet = next(value for value, key in facets if blocks[key] == b"AccentColor")
    if any(blocks[key] == COLOR for _, key in facets):
        raise ValueError("startup color already exists")
    facet = bytearray(blocks[old_facet])
    if len(facet) != 18 or facet[:16] != bytes.fromhex("000000000300010055000200d9001100"):
        raise ValueError("unexpected named-color facet")
    identifier = struct.unpack_from("<H", facet, 16)[0]
    used = {struct.unpack_from("<H", blocks[value], 16)[0] for value, _ in facets}
    new_identifier = next(i for i in range(1, 65536) if i not in used)
    struct.pack_into("<H", facet, 16, new_identifier)
    old_rendition = [(value, key) for value, key in renditions
                     if struct.unpack_from("<H", blocks[key], 10)[0] == identifier]
    if len(old_rendition) != 1:
        raise ValueError("unexpected color variants")
    value, key = old_rendition[0]
    color = bytearray(blocks[value])
    if len(color) != 260 or color[40:51] != b"AccentColor" or color[-48:-44] != b"RLOC":
        raise ValueError("unexpected color rendition")
    color[40:51] = COLOR
    struct.pack_into("<4d", color, len(color)-32, 0.01, 0.02, 0.075, 1.0)
    rendition_key = bytearray(blocks[key])
    struct.pack_into("<H", rendition_key, 10, new_identifier)

    def insert(data):
        index = next(i for i in range(1, len(blocks)) if not blocks[i])
        blocks[index] = bytes(data)
        return index

    facets.append((insert(facet), insert(COLOR)))
    renditions.append((insert(color), insert(rendition_key)))
    facets.sort(key=lambda pair: blocks[pair[1]])
    # The pinned tree compares the encoded attribute bytes, not decoded IDs.
    key_order = lambda pair: blocks[pair[1]]
    if renditions[:-1] != sorted(renditions[:-1], key=key_order):
        raise ValueError("unexpected rendition comparator")
    renditions.sort(key=key_order)
    changed = {facet_index, rendition_index, variables[b"FACETKEYS"],
               variables[b"RENDITIONS"], variables[b"CARHEADER"]}
    for index, pairs, root_name in [(facet_index, facets, b"FACETKEYS"),
                                    (rendition_index, renditions, b"RENDITIONS")]:
        blocks[index] = struct.pack(">HHII", 1, len(pairs), 0, 0) + b"".join(struct.pack(">II", *pair) for pair in pairs)
        root = bytearray(blocks[variables[root_name]])
        struct.pack_into(">I", root, 16, len(pairs))
        blocks[variables[root_name]] = bytes(root)
    header = bytearray(blocks[variables[b"CARHEADER"]])
    if header[:4] != b"RATC" or struct.unpack_from("<I", header, 16)[0] != len(renditions)-1:
        raise ValueError("unexpected CARHEADER")
    struct.pack_into("<I", header, 16, len(renditions))
    blocks[variables[b"CARHEADER"]] = bytes(header)

    result = bytearray(catalog)
    for index, data in enumerate(blocks):
        if not data or (index not in changed and locations[index][1]):
            continue
        result.extend(b"\0" * (-len(result) % 16))
        locations[index] = (len(result), len(data))
        result.extend(data)
    result.extend(b"\0" * (-len(result) % 16))
    new_index = len(result)
    table = struct.pack(">I", count) + b"".join(struct.pack(">II", *item) for item in locations) + struct.pack(">II", 0, 0)
    result.extend(table)
    struct.pack_into(">I", result, 12, sum(bool(length) for _, length in locations))
    struct.pack_into(">II", result, 16, new_index, len(table))
    return bytes(result)


if __name__ == "__main__":
    baseline = Path(__file__).resolve().parents[1] / "dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb"
    out = baseline.parents[1] / "build/audit"
    out.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(get_tar_member(read_ar(baseline.read_bytes()), "data.tar"))) as archive:
        entries = {m.name.lstrip("./"): archive.extractfile(m).read() for m in archive if m.isfile()}
    (out / "StartupAssets.car").write_bytes(add_startup_color(entries[APP+"Assets.car"]))
    (out / "NWBootPic.png").write_bytes(entries[APP+"NukeWirelessIcon.png"])
    patch_splash_names(entries[APP+"HarpyReloaded"])
