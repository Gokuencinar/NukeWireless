#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/bluetooth
mkdir -p "$out"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -fobjc-arc -fblocks -O2 -fPIC -dynamiclib \
  -framework Foundation -Wl,-fatal_warnings -Wl,-install_name,@rpath/NukeBluetoothBridge.dylib \
  src/bluetooth/NWBTBridge.m src/bluetooth/NWBTController.m -o "$out/NukeBluetoothBridge.dylib"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -Wall -Wextra -Werror -Werror=unguarded-availability -fobjc-arc -fblocks -O2 \
  -framework Foundation -Wl,-fatal_warnings -Wl,-rpath,@executable_path/../lib \
  src/bluetooth/NWBTInspector.m "$out/NukeBluetoothBridge.dylib" -o "$out/nwbt-inspect"
python3 scripts/bluetooth_manifest.py
file "$out/NukeBluetoothBridge.dylib" "$out/nwbt-inspect"
