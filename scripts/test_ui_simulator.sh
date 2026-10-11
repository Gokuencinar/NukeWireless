#!/bin/bash
set -euo pipefail
minimum_ios="${NW_MIN_IOS:-16.3}"
case "$minimum_ios" in
  15.0|16.3) ;;
  *) echo "Unsupported simulator deployment target: $minimum_ios" >&2; exit 1 ;;
esac
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
xcrun --sdk iphonesimulator clang -arch "$arch" "-mios-simulator-version-min=$minimum_ios" -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -fobjc-arc -fblocks -fPIC -O2 -dynamiclib -DNW_UI_TESTING \
  -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework CoreBluetooth -framework SystemConfiguration \
  -o "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  src/NukeWirelessInfo.m src/NWDiagnostics.m src/NWDiagnosticReport.m src/NWTaskDiagnostics.m src/NWMainTabs.m src/NWAppearance.m src/NWDeviceBrowser.m src/NWDeviceActions.m src/NWHotspot.m src/NWBluetooth.m src/NWBluetoothCatalog.m src/NWBLE.m src/NWBLEAdvertisement.m src/NWScanBridge.m src/NWResources.m src/NWLanguage.m src/NWPolicy.c tests/UIRegressionStub.c tests/DeviceActionsFixture.m
xcrun --sdk iphonesimulator swiftc -target "$arch-apple-ios$minimum_ios-simulator" -sdk "$sdk" -parse-as-library \
  tests/UIRegression.swift "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks -o "$out/UIRegression.app/UIRegression"
python3 - "$out/UIRegression.app/Info.plist" "$minimum_ios" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='app.nukewireless.ui-regression', CFBundleName='UIRegression',
        CFBundleExecutable='UIRegression', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1', MinimumOSVersion=sys.argv[2], UILaunchScreen={},
        NukeWirelessUIIntegration='embedded-required-v1',
        NSBluetoothAlwaysUsageDescription='Scan nearby BLE devices',
        UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': False}), f)
PY
python3 scripts/language_catalog.py "$out/UIRegression.app"
codesign -s - --force "$out/UIRegression.app/Frameworks/NukeWirelessInfo.dylib"
codesign -s - --force "$out/UIRegression.app"
device="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')"
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
python3 - "$out/runtime.json" "$device" "$minimum_ios" <<'PY'
import json, subprocess, sys
inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
runtime, phone = next((runtime, phone) for runtime, phones in inventory['devices'].items()
                      for phone in phones if phone['udid'] == sys.argv[2])
with open(sys.argv[1], 'w', encoding='utf-8') as stream:
    json.dump(dict(runtime=runtime, device=phone['name'], deployment_target=sys.argv[3],
                   physical_device=False), stream, indent=2)
PY
xcrun simctl install "$device" "$out/UIRegression.app"
container="$(xcrun simctl get_app_container "$device" app.nukewireless.ui-regression data)"
for language in en es; do
rm -f "$container/Documents/ui-regression.json" "$container/Documents/ui-initial.json" "$container/Documents"/resume-*.json
xcrun simctl launch "$device" app.nukewireless.ui-regression --language "$language"
for attempt in $(seq 1 30); do
  if [ -f "$container/Documents/resume-ready-0.json" ]; then break; fi
  sleep 2
done
python3 - "$container/Documents/ui-initial.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: result=json.load(f)
print('Initial navigation regression:', result)
assert result['passed'], result
PY
for phase in 0 1 2 3; do
  for attempt in $(seq 1 15); do
    if [ -f "$container/Documents/resume-ready-$phase.json" ]; then break; fi
    sleep 1
  done
  xcrun simctl launch "$device" com.apple.Preferences
  sleep 3
  # Bring the same suspended process back, preserving its SwiftUI state.
  xcrun simctl launch "$device" app.nukewireless.ui-regression
  for attempt in $(seq 1 20); do
    if [ -f "$container/Documents/resume-done-$phase.json" ]; then break; fi
    sleep 1
  done
  python3 - "$container/Documents/resume-ready-$phase.json" "$container/Documents/resume-done-$phase.json" <<'PY'
import json,sys
with open(sys.argv[1]) as f: before=json.load(f)
with open(sys.argv[2]) as f: after=json.load(f)
print('Real background/foreground regression:', before, after)
assert before['prepared'] and after['result'] == 0 and after['background_seen']
assert before['pid'] == after['pid'] and before['phase'] == after['phase']
PY
  cp "$container/Documents/resume-ready-$phase.json" "$out/$language-resume-ready-$phase.json"
  cp "$container/Documents/resume-done-$phase.json" "$out/$language-resume-done-$phase.json"
  cp "$container/Documents/resume-$phase.png" "$out/$language-resume-$phase.png"
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
for snapshot in hotspot hotspot-actions-dark diagnostic-emission diagnostic-back diagnostic-info diagnostics diagnostics-dark catalog-0 catalog-1 catalog-2 catalog-3 catalog-dark catalog-single catalog-active catalog-stopping catalog-error browser-actions browser-rename; do
  cp "$container/Documents/$snapshot.png" "$out/$language-$snapshot.png"
done
done
