"""Read the installed layout from the same constants compiled into the helpers."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src/NWInstallLayout.h").read_text(encoding="utf-8")
def constant(name):
    values = re.findall(r'^#define ' + re.escape(name) + r' "([^"\n]+)"$', HEADER, re.M)
    if len(values) != 1:
        raise ValueError("missing or ambiguous layout constant: " + name)
    return values[0]

EXECUTABLE = constant("NWInstalledExecutable")
APP = "Applications/" + constant("NWInstalledAppDirectory") + "/"
HELPERS = constant("NWInstalledHelperDirectory").lstrip("/")
APP_SUFFIX = constant("NWInstalledAppSuffix")
AEGIS_SUFFIX = "/" + HELPERS + "aegis"
if APP_SUFFIX != "/" + APP + EXECUTABLE:
    raise ValueError("inconsistent app layout")

def rename_path(name):
    """Translate pinned baseline paths, including their directory entries."""
    for old, new in [("Applications/HarpyReloaded.app/HarpyReloaded", APP + EXECUTABLE),
                     ("Applications/HarpyReloaded.app", APP.rstrip("/")),
                     ("usr/libexec/harpy-reloaded", HELPERS.rstrip("/"))]:
        if name == old or name.startswith(old + "/") or name == old + ".roothidepatch":
            return new + name[len(old):]
    return name
