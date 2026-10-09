"""Archive helpers for the Nuke Wireless RootHide package.

The original maintainer scripts are treated as data and are never executed.
"""

from __future__ import annotations

import gzip
import hashlib
import io
import os
from pathlib import Path
import tarfile


SOURCE = Path(os.environ.get("NUKEWIRELESS_SOURCE_DEB", ""))  # Legacy builder compatibility.



def read_ar(data: bytes) -> dict[str, bytes]:
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("not an ar archive")
    parts: dict[str, bytes] = {}
    offset = 8
    while offset < len(data):
        header = data[offset : offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError("invalid ar header")
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        parts[name] = data[offset + 60 : offset + 60 + size]
        offset += 60 + size + size % 2
    return parts


def pack_ar(parts: list[tuple[str, bytes]]) -> bytes:
    out = bytearray(b"!<arch>\n")
    for name, data in parts:
        if len(name) > 15:
            raise ValueError("ar member name too long")
        header = (
            f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{format(0o100644, 'o'):<8}{len(data):<10}`\n"
        ).encode("ascii")
        assert len(header) == 60
        out.extend(header)
        out.extend(data)
        if len(data) % 2:
            out.extend(b"\n")
    return bytes(out)


def tar_bytes(entries: list[tuple[tarfile.TarInfo, bytes | None]]) -> bytes:
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz", format=tarfile.GNU_FORMAT) as tf:
        for info, data in entries:
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "wheel"
            tf.addfile(info, io.BytesIO(data) if data is not None else None)
    return stream.getvalue()


def regular(path: str, data: bytes, mode: int = 0o644) -> tuple[tarfile.TarInfo, bytes]:
    info = tarfile.TarInfo("./" + path)
    info.mode = mode
    info.size = len(data)
    return info, data


def directory(path: str, mode: int = 0o755) -> tuple[tarfile.TarInfo, None]:
    info = tarfile.TarInfo("./" + path.rstrip("/") + "/")
    info.type = tarfile.DIRTYPE
    info.mode = mode
    return info, None


def symlink(path: str, target: str) -> tuple[tarfile.TarInfo, None]:
    info = tarfile.TarInfo("./" + path)
    info.type = tarfile.SYMTYPE
    info.mode = 0o777
    info.linkname = target
    return info, None


def get_tar_member(parts: dict[str, bytes], prefix: str) -> bytes:
    found = [(name, data) for name, data in parts.items() if name.startswith(prefix)]
    if len(found) != 1:
        raise ValueError(f"expected exactly one {prefix} member")
    return found[0][1]


