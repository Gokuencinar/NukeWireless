"""Package layouts, independent of CPU slices and native radio support."""

SCHEMES = {
    "roothide": ("", "usr/lib/TweakInject", "iphoneos-arm64e", "RootHide"),
    "rootless": ("var/jb/", "Library/MobileSubstrate/DynamicLibraries", "iphoneos-arm64", "Dopamine rootless"),
    "rootful": ("", "Library/MobileSubstrate/DynamicLibraries", "iphoneos-arm", "Rootful"),
}


def ordered_entries(entries):
    """Keep parents before children and reject duplicate files and collisions."""
    import copy
    from pathlib import PurePosixPath
    from package_utils import directory

    files, dirs = {}, {}
    for member, data in entries:
        name = member.name.removeprefix("./").strip("/")
        if not name:
            continue
        if ".." in PurePosixPath(name).parts:
            raise ValueError("unsafe package path: " + name)
        member = copy.copy(member)
        member.name = "./" + name
        if member.isdir():
            dirs.setdefault(name, (member, None))
        else:
            if name in files:
                raise ValueError("duplicate package file: " + name)
            files[name] = (member, data)
        for parent in PurePosixPath(name).parents:
            path = parent.as_posix()
            if path != ".":
                dirs.setdefault(path, directory(path))
    if files.keys() & dirs.keys():
        raise ValueError("package file/directory collision")
    return ([dirs[name] for name in sorted(dirs, key=lambda name: (name.count("/"), name))]
            + [files[name] for name in sorted(files)])
