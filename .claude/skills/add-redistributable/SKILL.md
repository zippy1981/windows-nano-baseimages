---
name: add-redistributable
description: How to add a Visual C++ runtime DLL from System32 to nanoserver-base - confirm a downstream image needs it, add it to redistributables.json, run the name and metadata checks locally, and update the README, tests and smoke tests. Use for a missing-redistributable issue, when a program on the base fails with 0xC0000135, or when bumping the Visual C++ redistributable.
---

# Add a Visual C++ redistributable DLL

nanoserver-base copies the Visual C++ runtime DLLs listed in `images/nanoserver-base/redistributables.json` from a Server Core stage that installed Microsoft's redistributable, into `C:\Windows\System32` ([ADR 0009](../../../docs/adr/0009-the-visual-cpp-runtime-is-copied-into-system32-from-the-redistributable.md)). Each DLL must pass the checks in `images/nanoserver-base/Redistributable.psm1`, or the build fails.

## 1. Confirm the DLL is needed

Add a DLL only when a real image needs it, usually from a [missing-redistributable issue](../../../.github/ISSUE_TEMPLATE/missing-redistributable.yml).

- Reproduce the failure on the base: the program exits with `-1073741515` (`0xC0000135`, a DLL is missing).
- List what the program imports, on any Windows host with the program unpacked: `dumpbin /dependents program.exe`, or [Dependencies](https://github.com/lucasg/Dependencies). Check the DLLs it loads at run time too, such as plugins.
- The name must match `^(vcruntime|msvcp|vcomp|concrt|msvcr)[0-9]+(_[0-9]+)?[.]dll$`. Names such as `msvcp140_atomic_wait.dll` or `msvcp_win.dll` don't, and can't be added this way. Raise those with the user.
- Check that Nano Server doesn't already ship it, on all three versions, since the base must never replace a Windows file:

  ```powershell
  foreach ($v in 2019, 2022, 2025) { docker run --rm mcr.microsoft.com/windows/nanoserver:ltsc$v-amd64 cmd /c "dir /b C:\Windows\System32\vcomp140.dll" }
  ```

## 2. Run the checks locally

On a Windows host with the redistributable installed (most developer machines, and GitHub's `windows-latest`), from the repo root:

```powershell
Import-Module ./images/nanoserver-base/Redistributable.psm1 -Force
Test-RedistributableName -Name vcomp140.dll
Get-RedistributableProblem -Path C:\Windows\System32\vcomp140.dll   # prints nothing when the file passes
```

The image build runs the same checks under Windows PowerShell 5.1 on Server Core, so keep `Redistributable.psm1` free of PowerShell 7-only syntax.

## 3. Add it

- **`images/nanoserver-base/redistributables.json`:** add `{ "name": "..." }`. Which executables need it is a downstream concern, so it isn't recorded here. Link the issue in the pull request instead.
- **`README.md`:** add a row to the table under "Visual C++ runtime DLLs", with its file version.
- **`images/nanoserver-base/README.md`:** add the name to the Visual C++ row of "What's in it".
- **`docs/adr/0009`:** update the DLL list in its Context if the new DLL changes the reasoning.

The Pester tests, both smoke tests and the `NOTICE.txt` written in the build all read the allowlist, so they pick the new DLL up without edits.

## 4. Test

```powershell
Invoke-Pester -Path tests/Redistributable.Tests.ps1 -Output Detailed
./images/nanoserver-base/build.cmd 2019    # then 2022 and 2025
./images/nanoserver-base/smoke-test.ps1 -Image nanoserver-base:ltsc2019 -SkipArchives
./images/nanoserver-base-pwsh/smoke-test.ps1 -Image nanoserver-base:ltsc2019-pwsh
```

Clean up afterwards with the `safe-docker-cleanup` skill. Then check that the image that needed the DLL now runs on the base without copying it in.

## Bumping the redistributable

1. Find the current versioned URL: `curl -sIL https://aka.ms/vc14/vc_redist.x64.exe | grep -i ^location`. The last `Location` is a `download.visualstudio.microsoft.com/download/pr/<guid>/<SHA-256>/VC_redist.x64.exe` URL.
2. Download it and check that `(Get-FileHash VC_redist.x64.exe).Hash` equals the SHA-256 in the URL, that `Get-AuthenticodeSignature` is `Valid` for Microsoft Corporation, and read `ProductVersion` from `(Get-Item VC_redist.x64.exe).VersionInfo`.
3. Update the `VCREDIST_VERSION`, `VCREDIST_URL` and `VCREDIST_SHA256` block in `images/nanoserver-base/Dockerfile`, and every version in the README tables.
4. Build and smoke-test on all three versions. The build fails if a DLL's file version isn't `VCREDIST_VERSION`.
