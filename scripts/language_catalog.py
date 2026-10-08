"""Generate identical native-language catalogs for the app and extension bundle."""
import json
import plistlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def native_strings(language):
    catalog = json.loads((ROOT / 'resources/NativeCatalog.json').read_text(encoding='utf8'))
    lines = []
    for key, values in catalog.items():
        if set(values) != {'en', 'es'} or not all(values.values()):
            raise ValueError(f'incomplete native translation: {key}')
        lines.append(f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(values[language], ensure_ascii=False)};')
    return ('\n'.join(lines) + '\n').encode('utf8')

def fixture(app):
    bundle = app / 'NukeWirelessResources.bundle'
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='app.nukewireless.resources',
        CFBundleName='NukeWireless', CFBundleDevelopmentRegion='en', CFBundleLocalizations=['en', 'es'],
        CFBundlePackageType='BNDL')))
    shutil.copyfile(ROOT / 'resources/CreditsAvatar.png', bundle / 'CreditsAvatar.png')
    shutil.copytree(ROOT / 'resources/brands', bundle / 'brands', dirs_exist_ok=True)
    for language in ['en', 'es']:
        nested = bundle / f'{language}.lproj'; nested.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / f'resources/{language}.lproj/Localizable.strings', nested / 'Localizable.strings')
        (nested / 'Native.strings').write_bytes(native_strings(language))
        main = app / f'{language}.lproj'; main.mkdir(exist_ok=True)
        (main / 'Localizable.strings').write_bytes(native_strings(language))

if __name__ == '__main__':
    fixture(Path(sys.argv[1]))
