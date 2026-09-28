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
  -Wall -Wextra -Werror -fobjc-arc -fblocks -fPIC -O2 -dynamiclib \
  -Wl,-undefined,dynamic_lookup -framework UIKit -framework Foundation \
  -framework QuartzCore -framework SystemConfiguration \
  -o build/audit/NukeWirelessInfo_ios.dylib \
  src/NukeWirelessInfo.m src/NWScanBridge.m src/NWResources.m src/NWPolicy.c src/NWRefreshThunk.S
file build/audit/NukeWirelessInfo_ios.dylib
python3 scripts/build_manifest.py
