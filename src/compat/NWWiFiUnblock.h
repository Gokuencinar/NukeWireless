#pragma once
#include <objc/runtime.h>

// MCCommands class method, verified by NWScanBridge's v24@0:8@16 contract.
// Callback owns only the matching registered task; no Swift ABI or hook backend.
BOOL NWInstallWiFiUnblock(Class commands, void (*prepare)(const char *), void (*stop)(const char *));
