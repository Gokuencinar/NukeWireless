#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
out="$PWD/build/ui"
mkdir -p "$out/UIRegression.app/Frameworks"
xcrun --sdk iphonesimulator clang -arch "$arch" -mios-simulator-version-min=16.3 -isysroot "$sdk" \
  -Wall -Wextra -Werror -fobjc-arc -fblocks -fPIC -O2 -dynamiclib -DNW_UI_TESTING \
  -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework SystemConfiguration \
  -o "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  src/NukeWirelessInfo.m src/NWScanBridge.m src/NWResources.m src/NWPolicy.c tests/UIRegressionStub.c
xcrun --sdk iphonesimulator swiftc -target "$arch-apple-ios16.3-simulator" -sdk "$sdk" -parse-as-library \
  tests/UIRegression.swift "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks -o "$out/UIRegression.app/UIRegression"
python3 - "$out/UIRegression.app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='app.nukewireless.ui-regression', CFBundleName='UIRegression',
        CFBundleExecutable='UIRegression', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='16.3', UILaunchScreen={},
        UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': False}), f)
PY
codesign -s - --force "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib"
codesign -s - --force "$out/UIRegression.app"
device="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$out/UIRegression.app"
xcrun simctl launch "$device" app.nukewireless.ui-regression
container="$(xcrun simctl get_app_container "$device" app.nukewireless.ui-regression data)"
for attempt in $(seq 1 30); do
  if [ -f "$container/Documents/ui-regression.json" ]; then break; fi
  sleep 2
done
python3 - "$container/Documents/ui-regression.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: result=json.load(f)
print('SwiftUI tab regression:', result)
assert result['passed'], result
PY
xcrun simctl terminate "$device" app.nukewireless.ui-regression
