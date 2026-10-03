#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audit
python3 scripts/language_catalog.py build/audit
clang -Wall -Wextra -Werror src/NWPolicy.c tests/test_policy.c -o build/audit/test_policy
build/audit/test_policy
clang -Wall -Wextra -Werror -fobjc-arc -fblocks -framework Foundation src/NWResources.m src/NWLanguage.m src/NWPolicy.c tests/test_resources.m -o build/audit/test_resources
build/audit/test_resources
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.3 -isysroot "$sdk" \
  -Wall -Wextra -Werror -fobjc-arc -fblocks -fPIC -O2 -dynamiclib \
  -Wl,-fatal_warnings -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework SystemConfiguration \
  -o build/audit/NukeWirelessInfo_ios.dylib \
  src/NukeWirelessInfo.m src/NWScanBridge.m src/NWResources.m src/NWLanguage.m src/NWPolicy.c src/NWRefreshThunk.S
file build/audit/NukeWirelessInfo_ios.dylib
xcrun --sdk iphoneos ibtool --compile build/audit/NukeLaunch.storyboardc resources/NukeLaunch.storyboard \
  --minimum-deployment-target 16.3 --target-device iphone --target-device ipad
python3 scripts/startup_resources.py
xcrun --sdk iphoneos assetutil --info resources/startup/OriginalAssets.car > build/audit/original-assets.json
xcrun --sdk iphoneos assetutil --info build/audit/StartupAssets.car > build/audit/startup-assets.json
python3 - <<'PY'
import json
from pathlib import Path
assets = json.loads(Path('build/audit/startup-assets.json').read_text())
original = json.loads(Path('build/audit/original-assets.json').read_text())
colors = [a for a in assets if a.get('AssetType') == 'Color']
print('Original assets:', len(original), 'new assets:', len(assets), 'colors:', colors)
assert any(a.get('Name') == 'NWBootColor' for a in colors), colors
assert any(a.get('Name') == 'AccentColor' for a in assets), colors
before = sorted(json.dumps(a, sort_keys=True) for a in original if 'AssetType' in a)
after = sorted(json.dumps(a, sort_keys=True) for a in assets if 'AssetType' in a and a.get('Name') != 'NWBootColor')
assert before == after, 'Original catalog renditions changed'
print('Apple assetutil reads the new splash color and the preserved original catalog.')
PY
python3 scripts/build_manifest.py
