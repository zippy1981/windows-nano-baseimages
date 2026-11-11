# windows-nano-baseimages

Production-quality Windows Nano Server base images for ltsc2019, ltsc2022 and ltsc2025. They're light, but usable out of the box.

## Images

| Image | Tags | What's in it |
| --- | --- | --- |
| [`zippy1981/nanoserver-base`](images/nanoserver-base/README.md) | `ltsc2019`, `ltsc2022`, `ltsc2025` | Nano Server with `tar` (libarchive bsdtar), `bsdcpio`, `bsdcat`, `bsdunzip`, `jq`, `yq` and `edit` first on `PATH`, and the [Visual C++ runtime DLLs](#visual-c-runtime-dlls) in `System32` |
| `zippy1981/nanoserver-base` | `ltsc2019-pwsh`, `ltsc2022-pwsh`, `ltsc2025-pwsh` | The same, plus PowerShell 7 |

Each tag also has an immutable `ltsc<ver>[-pwsh]-<os-build>-<sha7>` form ([ADR 0008](docs/adr/0008-images-build-on-self-hosted-runners-and-publish-from-main.md)).

| Tool | Source |
| --- | --- |
| `tar` and the other libarchive tools | Compiled here from [libarchive](https://github.com/libarchive/libarchive) with MXE, on GitHub-hosted Linux runners, and published as this repo's `static-X.Y.Z` releases |
| `curl` | Windows' own `C:\Windows\System32\curl.exe`, which uses Schannel and the Windows certificate store. curl.se's build can't verify HTTPS on Nano Server ([ADR 0007](docs/adr/0007-curl-is-the-windows-curl-with-schannel.md)). |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) releases |
| `yq` | [mikefarah/yq](https://github.com/mikefarah/yq) v4 releases |
| `edit` | [Microsoft Edit](https://github.com/microsoft/edit) 2.0 |
| `pwsh` | [PowerShell 7](https://github.com/PowerShell/PowerShell), in the `-pwsh` tags |

More tools will be added the same way. Every download is pinned by version and SHA-256, and every image ships the licences of what it contains. A daily workflow opens a pull request when a pinned tool has a new release.

## Visual C++ runtime DLLs

Nano Server doesn't ship the Visual C++ runtime and can't run its installer, so executables that need it fail to start with `0xC0000135`. nanoserver-base puts these DLLs in `C:\Windows\System32` ([#14](https://github.com/zippy1981/windows-nano-baseimages/issues/14), [ADR 0009](docs/adr/0009-the-visual-cpp-runtime-is-copied-into-system32-from-the-redistributable.md)):

| DLL | File version |
| --- | --- |
| `vcruntime140.dll` | 14.51.36247.0 |
| `vcruntime140_1.dll` | 14.51.36247.0 |
| `msvcp140.dll` | 14.51.36247.0 |

They come from the Microsoft Visual C++ v14 Redistributable (x64) 14.51.36247.0, which a Server Core build stage downloads from a pinned URL, checks against Microsoft's SHA-256 and installs. Only the DLLs in [redistributables.json](images/nanoserver-base/redistributables.json) are copied out, and each one must pass these checks first, or the build fails:

1. Its name matches `^(vcruntime|msvcp|vcomp|concrt|msvcr)[0-9]+(_[0-9]+)?[.]dll$`.
2. Its version resource has CompanyName `Microsoft Corporation`, a ProductName that starts with `Microsoft`, and an OriginalFilename equal to its name.
3. Its Authenticode signature is valid, its signer is Microsoft Corporation, and it chains to Microsoft Root Certificate Authority 2010 or 2011.
4. Its file version is the pinned redistributable's version.

The checks are in [Redistributable.psm1](images/nanoserver-base/Redistributable.psm1) and are tested over the allowlist by [tests/Redistributable.Tests.ps1](tests/Redistributable.Tests.ps1). The smoke tests check that each DLL is in `System32` on every version, and the `-pwsh` smoke test loads each one as `ContainerUser`. [tests/downstream](tests/downstream/smoke-test.ps1) builds a throwaway image on the new base with executables that need the runtime but bring none of their own, and checks that they run as `ContainerUser` on every version. Where the DLLs came from and their licence terms are in `C:\tools\licenses\vcredist\NOTICE.txt`.

If your image needs a runtime DLL that isn't listed, [open a missing-redistributable issue](https://github.com/zippy1981/windows-nano-baseimages/issues/new?template=missing-redistributable.yml). To add one, follow the [add-redistributable skill](.claude/skills/add-redistributable/SKILL.md).

## libarchive for Windows

`tar.exe` in the images is this repo's own build of libarchive's `bsdtar`, cross-compiled with [MXE](https://mxe.cc) on GitHub-hosted Linux runners. For libarchive `X.Y.Z` there are two releases:

- `vX.Y.Z`: `libarchive-X.Y.Z-windows-x64-static.zip` and `libarchive-X.Y.Z-windows-x64-shared.zip`, the full static and shared builds with headers and libraries.
- `static-X.Y.Z`: `libarchive-X.Y.Z-windows-x64-static-tools.zip`, just the static `bsdtar`, `bsdcpio`, `bsdcat` and `bsdunzip` with their licences.

A daily workflow builds each new upstream release. To build one by hand:

```bash
gh workflow run build-libarchive.yml --repo zippy1981/windows-nano-baseimages -f version=3.8.11
```

[docs/libarchive-build.md](docs/libarchive-build.md) covers the architecture, the MXE image, the feature matrix, local builds, permissions, troubleshooting, security and known limitations.

## Status

Work is tracked in [issues](https://github.com/zippy1981/windows-nano-baseimages/issues). Issue #1 is the libarchive build and release system, which the images depend on. Decisions are in [docs/adr](docs/adr/README.md) and plans in [plans](plans/).

## Contributing with Claude Code

`CLAUDE.md` holds the repo's conventions and the shared-host safety rules. `.claude/agents/` has the agents that implement the issues: start with `issue-implementer`. Markdown must pass `npx -y markdownlint-cli --dot '**/*.md'`, and `pre-commit run --all-files` runs it.
