#!/bin/bash
# Build candidates only; no install, publication or device actions.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audit
python3 scripts/language_catalog.py build/audit
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -fobjc-arc -fblocks -fPIC -O2 -dynamiclib \
  -Wl,-fatal_warnings -Wl,-install_name,@rpath/NukeWirelessInfo.dylib \
  -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
  -framework CoreBluetooth -framework SystemConfiguration -o build/audit/NukeWirelessInfo_ios.dylib \
  src/NukeWirelessInfo.m src/NWAppearance.m src/NWDeviceBrowser.m src/NWBluetooth.m src/NWBLE.m src/NWBLEAdvertisement.m src/NWScanBridge.m src/NWResources.m src/NWLanguage.m src/NWPolicy.c src/NWRefreshThunk.S
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -Wall -Wextra -Werror -Wno-unused-parameter -x objective-c -fno-objc-arc -fblocks -fPIC -O2 -dynamiclib -Wl,-fatal_warnings \
  -Wl,-install_name,@rpath/NukeWirelessPaths.dylib \
  -framework Foundation -framework UIKit -framework CoreBluetooth -framework SystemConfiguration \
  src/compat/NWLegacyPaths.c -o build/audit/NukeWirelessPaths_ios.dylib
xcrun --sdk iphoneos ibtool --compile build/audit/NukeLaunch.storyboardc resources/NukeLaunch.storyboard \
  --minimum-deployment-target 15.0 --target-device iphone --target-device ipad
python3 scripts/startup_resources.py
python3 scripts/build_manifest.py --target arm64-ios15.0
python3 scripts/compat_manifest.py
file build/audit/NukeWirelessInfo_ios.dylib build/audit/NukeWirelessPaths_ios.dylib
