# 0009. The Visual C++ runtime is copied into System32 from the redistributable

- Status: Proposed
- Date: 2026-11-08
- Deciders: zippy1981
- Related: [#14](https://github.com/zippy1981/windows-nano-baseimages/issues/14), [zippy1981/windows-nano-demos#71](https://github.com/zippy1981/windows-nano-demos/issues/71), [0006](0006-tools-take-precedence-over-system32-through-the-machine-path.md)

## Context

Executables built with Visual C++ need `vcruntime140.dll`, `vcruntime140_1.dll` and `msvcp140.dll`. Nano Server doesn't ship them on any LTSC version, and it can't run Microsoft's redistributable installer. So each downstream image that needs them installs the redistributable in its own Server Core stage, from the unpinned `https://aka.ms/vc14/vc_redist.x64.exe`, and copies the DLLs out.

## Decision

nanoserver-base installs a pinned Visual C++ v14 redistributable in a throwaway Server Core stage (`vcredist`), and copies the DLLs listed in `images/nanoserver-base/redistributables.json` into `C:\Windows\System32`.

- **Pin:** the versioned `download.visualstudio.microsoft.com` URL that `aka.ms/vc14/vc_redist.x64.exe` redirects to. Its path contains Microsoft's SHA-256 of the installer, which the build checks.
- **Checks:** before copying, `Redistributable.psm1` requires each file's name to match `^(vcruntime|msvcp|vcomp|concrt|msvcr)[0-9]+(_[0-9]+)?[.]dll$`. Its version resource must say Microsoft (CompanyName, ProductName and an OriginalFilename equal to its name). Its Authenticode signature must be valid, signed by Microsoft Corporation, and chain to Microsoft Root Certificate Authority 2010 or 2011. Each FileVersion must also equal the pinned redistributable's version. If any check fails, nothing is copied and the build fails.
- **Location:** `System32`, not `C:\tools\bin`. None of these names exists in Nano Server's `System32`, so no Windows file is replaced, which keeps to [0006](0006-tools-take-precedence-over-system32-through-the-machine-path.md).
- **Licence:** the base image counts as an application under Microsoft's terms for redistributing the Visual C++ files (the owner's decision, on [#15](https://github.com/zippy1981/windows-nano-baseimages/pull/15)). `C:\tools\licenses\vcredist\NOTICE.txt` records the installer's version, URL and SHA-256, and points to Microsoft's terms for redistributing the Visual C++ files.

## Consequences

- Downstream images drop their Server Core stage and stop copying DLLs. They get a pinned, verified runtime instead of whatever `aka.ms` served on the day they were built.
- Every nanoserver-base tag carries about 0.9 MB of DLLs, including the images that don't need them.
- Bumping the redistributable means changing three `ENV` values. The version check fails the build if the DLLs and the pin disagree.
- An image that needs another runtime DLL (for example `vcomp140.dll`) asks for it through the missing-redistributable issue template. It's added to the allowlist following the `add-redistributable` skill.

## Alternatives considered

- **Put the DLLs in `C:\tools\bin`:** found through `PATH`, but `PATH` comes last in the DLL search order. Programs that call `SetDefaultDllDirectories` or load with `LOAD_LIBRARY_SEARCH_SYSTEM32` don't search it.
- **Keep it in each downstream image:** that's the duplication #14 removes, and each copy came from an unpinned URL.
- **Copy every `vcruntime*`, `msvcp*`, `vcomp*` and `concrt*` file the redistributable installs:** more weight and more to verify, for DLLs no image has asked for.
