#!/bin/bash
# Build candidates only; no install, publication or device actions.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audit
# Use the complete current extension and its tests; keep the normal dev target.
NW_MIN_IOS=15.0 bash scripts/build_extension.sh
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -Wno-unused-parameter -x objective-c -fno-objc-arc -fblocks -fPIC -O2 -dynamiclib -Wl,-fatal_warnings \
  -Wl,-install_name,@rpath/NukeWirelessPaths.dylib \
  -framework Foundation -framework UIKit -framework CoreBluetooth -framework SystemConfiguration \
  src/compat/NWLegacyPaths.c -o build/audit/NukeWirelessPaths_ios.dylib
bash scripts/build_bluetooth_inspector.sh
python3 scripts/compat_manifest.py
file build/audit/NukeWirelessInfo_ios.dylib build/audit/NukeWirelessPaths_ios.dylib
