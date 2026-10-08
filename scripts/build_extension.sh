#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audit
minimum_ios="${NW_MIN_IOS:-16.3}"
case "$minimum_ios" in
  15.0|16.3) ;;
  *) echo "Unsupported deployment target: $minimum_ios" >&2; exit 1 ;;
esac
python3 scripts/language_catalog.py build/audit
clang -Wall -Wextra -Werror tests/test_device_catalog.c -o build/audit/test_device_catalog
build/audit/test_device_catalog
clang -Wall -Wextra -Werror tests/test_catalog_profiles.c -o build/audit/test_catalog_profiles
build/audit/test_catalog_profiles
clang -Wall -Wextra -Werror src/NWPolicy.c tests/test_policy.c -o build/audit/test_policy
build/audit/test_policy
clang -Wall -Wextra -Werror -fobjc-arc -fblocks -framework Foundation src/NWResources.m src/NWLanguage.m src/NWPolicy.c tests/test_resources.m -o build/audit/test_resources
build/audit/test_resources
clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation src/NWBLEAdvertisement.m tests/test_ble_advertisement.m -o build/audit/test_ble_advertisement
build/audit/test_ble_advertisement
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 "-miphoneos-version-min=$minimum_ios" -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -fobjc-arc -fblocks -fPIC -O2 -dynamiclib \
  -Wl,-fatal_warnings -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework CoreBluetooth -framework SystemConfiguration \
  -o build/audit/NukeWirelessInfo_ios.dylib \
  src/NukeWirelessInfo.m src/NWMainTabs.m src/NWAppearance.m src/NWDeviceBrowser.m src/NWBluetooth.m src/NWBluetoothCatalog.m src/NWBLE.m src/NWBLEAdvertisement.m src/NWScanBridge.m src/NWResources.m src/NWLanguage.m src/NWPolicy.c src/NWRefreshThunk.S
file build/audit/NukeWirelessInfo_ios.dylib
xcrun --sdk iphoneos ibtool --compile build/audit/NukeLaunch.storyboardc resources/NukeLaunch.storyboard \
  --minimum-deployment-target "$minimum_ios" --target-device iphone --target-device ipad
python3 scripts/startup_resources.py
sips -g pixelWidth -g pixelHeight build/audit/NWBootPic.png
python3 scripts/build_manifest.py --target "arm64-ios$minimum_ios"
