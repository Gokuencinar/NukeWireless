#pragma once
#include <objc/runtime.h>

// MCCommands class method, verified by NWScanBridge's v24@0:8@16 contract.
// Callback owns only the matching registered task; no Swift ABI or hook backend.
BOOL NWInstallWiFiUnblock(Class commands, void (*prepare)(const char *), void (*stop)(const char *));

// Shared by Objective-C dispatch and the pinned native Swift entry. Nested calls
// for the same IP clean up only once; different IPs retain their own cleanup.
void NWPerformWiFiUnblock(id value, void (^original)(void));
