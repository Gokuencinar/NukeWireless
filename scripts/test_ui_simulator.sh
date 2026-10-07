#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
out="$PWD/build/ui"
mkdir -p "$out/UIRegression.app/Frameworks"
collect_ui_artifacts() {
  if [ -n "${container:-}" ]; then
    for path in "$container"/Documents/*.png "$container"/Documents/*.json; do
      if [ -f "$path" ]; then cp "$path" "$out/"; fi
    done
  fi
  for path in "$HOME"/Library/Logs/DiagnosticReports/UIRegression*.ips; do
    if [ -f "$path" ]; then cp "$path" "$out/"; fi
  done
}
trap collect_ui_artifacts EXIT
xcrun --sdk iphonesimulator clang -arch "$arch" -mios-simulator-version-min=16.3 -isysroot "$sdk" \
  -Wall -Wextra -Werror -fobjc-arc -fblocks -fPIC -O2 -dynamiclib -DNW_UI_TESTING \
  -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework CoreBluetooth -framework SystemConfiguration \
  -o "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  src/NukeWirelessInfo.m src/NWMainTabs.m src/NWAppearance.m src/NWDeviceBrowser.m src/NWBluetooth.m src/NWBluetoothCatalog.m src/NWBLE.m src/NWBLEAdvertisement.m src/NWScanBridge.m src/NWResources.m src/NWLanguage.m src/NWPolicy.c tests/UIRegressionStub.c
xcrun --sdk iphonesimulator swiftc -target "$arch-apple-ios16.3-simulator" -sdk "$sdk" -parse-as-library \
  tests/UIRegression.swift "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks -o "$out/UIRegression.app/UIRegression"
python3 - "$out/UIRegression.app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='app.nukewireless.ui-regression', CFBundleName='UIRegression',
        CFBundleExecutable='UIRegression', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion='16.3', UILaunchScreen={},
        NSBluetoothAlwaysUsageDescription='Scan nearby BLE devices',
        UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': False}), f)
PY
python3 scripts/language_catalog.py "$out/UIRegression.app"
codesign -s - --force "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib"
codesign -s - --force "$out/UIRegression.app"
device="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$out/UIRegression.app"
container="$(xcrun simctl get_app_container "$device" app.nukewireless.ui-regression data)"
for language in en es; do
rm -f "$container/Documents/ui-regression.json"
xcrun simctl launch "$device" app.nukewireless.ui-regression --language "$language"
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
cp "$container/Documents/ui-regression.json" "$out/$language-regression.json"
cp "$container/Documents/wifi.png" "$out/$language-wifi.png"
cp "$container/Documents/info.png" "$out/$language-info.png"
cp "$container/Documents/bluetooth.png" "$out/$language-bluetooth.png"
cp "$container/Documents/bluetooth-dark.png" "$out/$language-bluetooth-dark.png"
for snapshot in catalog-0 catalog-1 catalog-2 catalog-3 catalog-dark catalog-single catalog-active catalog-stopping catalog-error; do
  cp "$container/Documents/$snapshot.png" "$out/$language-$snapshot.png"
done
done
