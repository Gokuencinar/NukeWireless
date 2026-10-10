#pragma once
// Interoperability with the hash-pinned Swift executable, not product branding.
// Runtime classes, persistence keys and signing identity remain compatible.
// Legacy filesystem strings are translated to NWInstallLayout.h at runtime.
#define NWLegacyBundleID "me.midnightchips.harpy-reloaded"
#define NWLegacyExecutable "HarpyReloaded"
#define NWLegacyHelperDirectory "/usr/libexec/harpy-reloaded/"
#define NWLegacyCommandsClass "_TtC13HarpyReloaded10MCCommands"
#define NWLegacyScannerClass "_TtC13HarpyReloaded10LanScanner"
#define NWLegacyDeviceClass "_TtC13HarpyReloaded8MMDevice"
#define NWLegacyAliasesKey "HarpyRHDeviceAliases"
#define NWLegacyResolvedNamesKey "HarpyRHResolvedNames"
#define NWLegacyTitleShort "Harpy"
#define NWLegacyTitleSpaced "Harpy Reloaded"
#define NWLegacyTitleHyphenated "Harpy-Reloaded"
