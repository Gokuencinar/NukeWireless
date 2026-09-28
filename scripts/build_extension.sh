#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/audit
clang -Wall -Wextra -Werror src/NWPolicy.c tests/test_policy.c -o build/audit/test_policy
build/audit/test_policy
clang -Wall -Wextra -Werror -fobjc-arc -fblocks -framework Foundation src/NWResources.m src/NWPolicy.c tests/test_resources.m -o build/audit/test_resources
build/audit/test_resources
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.3 -isysroot "$sdk" \
  -Wall -Wextra -Werror -fobjc-arc -fblocks -fPIC -O2 -DNW_DIAGNOSTIC=1 -dynamiclib \
  -Wl,-fatal_warnings -Wl,-install_name,@rpath/NukeWirelessInfo.dylib -framework UIKit -framework Foundation \
  -framework QuartzCore -framework CoreGraphics -framework SystemConfiguration \
  -o build/audit/NukeWirelessInfo_ios.dylib \
  src/NukeWirelessInfo.m src/NWScanBridge.m src/NWResources.m src/NWPolicy.c src/NWRefreshThunk.S
file build/audit/NukeWirelessInfo_ios.dylib
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=16.3 -isysroot "$sdk" \
  -Wall -Wextra -Werror -fPIC -O2 -dynamiclib -Wl,-fatal_warnings \
  -o build/audit/NukeWirelessProbe.dylib tests/injection_probe.c
python3 scripts/build_manifest.py
