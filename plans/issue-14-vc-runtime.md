# Visual C++ runtime in nanoserver-base

## Goal

nanoserver-base ships the Visual C++ runtime DLLs that PHP, MySQL and Helix need, so downstream images stop copying them in from their own Server Core stages ([#14](https://github.com/zippy1981/windows-nano-baseimages/issues/14), [zippy1981/windows-nano-demos#71](https://github.com/zippy1981/windows-nano-demos/issues/71)).

## Context

- windows-nano-demos' PHP, MySQL and Helix images each install `https://aka.ms/vc14/vc_redist.x64.exe` (unpinned) in Server Core, and copy `vcruntime140.dll`, `vcruntime140_1.dll` and, for PHP and MySQL, `msvcp140.dll` into Nano Server's `System32`.
- Stock Nano Server ltsc2019, ltsc2022 and ltsc2025 have none of those three files. Their `System32` has only `msvcp_win.dll`, `msvcp110_win.dll`, `msvcrt.dll`, and on 2019 and 2022 `msvcp120.dll` and `msvcr120.dll`.
- `aka.ms/vc14/vc_redist.x64.exe` redirects to a versioned URL whose path contains the installer's SHA-256. On 2026-11-08 that was 14.51.36247.0, and its three DLLs have that file version.

## Decisions

Recorded in [ADR 0009](../docs/adr/0009-the-visual-cpp-runtime-is-copied-into-system32-from-the-redistributable.md).

- A separate `vcredist` Server Core stage installs the pinned redistributable. `Redistributable.psm1` checks the name, version resource, Authenticode signer and root, and file version of each allowlisted DLL, and copies nothing unless all pass.
- The DLLs go in `C:\Windows\System32`, not `C:\tools\bin`, because `PATH` is last in the DLL search order.
- The allowlist is `images/nanoserver-base/redistributables.json`: just the three confirmed DLLs. The tests, smoke tests and `NOTICE.txt` read it.
- Microsoft root CAs 2010 and 2011 are pinned by thumbprint. The chain check ignores expired certificates, because the signatures are timestamped and `Get-AuthenticodeSignature` has already validated them.

## Plan

### Phase 1: Image and checks

- [x] **container-author**: the `vcredist` stage, the `COPY` into `System32`, the header and the licence label. Accept: builds on 2019, 2022 and 2025.
- [x] **powershell-author**: `Redistributable.psm1`, `tests/Redistributable.Tests.ps1`, and the DLL checks in both smoke tests. Accept: Pester passes and PSScriptAnalyzer is clean at Warning.
- [ ] **workflow-author**: a `pester` job on `windows-latest` in `lint-scripts.yml`. Accept: green in CI, with actionlint.
- [x] **windows-container-tester**: both smoke tests on all three versions (locally, without the archives). Accept: the DLLs load as `ContainerUser` and are 14.51.36247.0.

- [x] **powershell-author**: `tests/downstream` builds a throwaway image `FROM` the base with PHP 8.5.12, MySQL 8.4.13 and Helix 25.07.1, which bring no runtime DLLs, and checks they run as `ContainerUser`. **workflow-author** runs it in `nanoserver-base.yml`. Accept: passes on 2019, 2022 and 2025.

### Phase 2: Docs

- [x] **adr**: ADR 0009.
- [x] README section, issue template `missing-redistributable.yml`, and the `add-redistributable` skill, linked from the README. Accept: markdownlint passes.

### Phase 3: Downstream

- [ ] **planning**: in windows-nano-demos#71, remove the VC++ stages from `nano-server-php`, `nano-server-mysql` and `nano-server-editors` once this is published. Accept: their smoke tests pass on all three versions on the new base.

## Risks

- **Licence of the redistributed DLLs:** Microsoft lets these files be redistributed with an application, under the Visual Studio licence terms. The owner decided that the base image counts as an application ([ADR 0009](../docs/adr/0009-the-visual-cpp-runtime-is-copied-into-system32-from-the-redistributable.md)). `NOTICE.txt` records the source and points to the terms.
- **A new redistributable changes the file versions:** the build fails on a mismatch, so the README can't drift. Bumps follow the skill.
- **A Server Core image ships its own, newer runtime:** the installer would exit 1638 and the build would fail. Mitigation: fails loudly; then decide whether to ship the newer copy.
