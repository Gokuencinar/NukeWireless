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
xcrun --sdk iphoneos assetutil --info build/audit/StartupAssets.car > build/audit/startup-assets.json
python3 - <<'PY'
import json
from pathlib import Path
assets = json.loads(Path('build/audit/startup-assets.json').read_text())
assert any(a.get('Name') == 'NWBootColor' and a.get('AssetType') == 'Color' for a in assets), assets
assert any(a.get('Name') == 'AccentColor' for a in assets), assets
print('Apple assetutil reads the new splash color and the preserved original catalog.')
PY
python3 scripts/build_manifest.py
