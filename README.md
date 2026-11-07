# windows-nano-baseimages

Production-quality Windows Nano Server base images for ltsc2019, ltsc2022 and ltsc2025. They're light, but usable out of the box.

## Images

| Image | Tags | What's in it |
| --- | --- | --- |
| [`zippy1981/nanoserver-base`](images/nanoserver-base/README.md) | `ltsc2019`, `ltsc2022`, `ltsc2025` | Nano Server with `tar` (libarchive bsdtar), `bsdcpio`, `bsdcat`, `bsdunzip`, `jq` and `edit` first on `PATH` |
| `zippy1981/nanoserver-base` | `ltsc2019-pwsh`, `ltsc2022-pwsh`, `ltsc2025-pwsh` | The same, plus PowerShell 7 |

Each tag also has an immutable `ltsc<ver>[-pwsh]-<os-build>-<sha7>` form ([ADR 0008](docs/adr/0008-images-build-on-self-hosted-runners-and-publish-from-main.md)).

| Tool | Source |
| --- | --- |
| `tar` and the other libarchive tools | Compiled here from [libarchive](https://github.com/libarchive/libarchive) with MXE, on GitHub-hosted Linux runners, and published as this repo's `static-X.Y.Z` releases |
| `curl` | Windows' own `C:\Windows\System32\curl.exe`, which uses Schannel and the Windows certificate store. curl.se's build can't verify HTTPS on Nano Server ([ADR 0007](docs/adr/0007-curl-is-the-windows-curl-with-schannel.md)). |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) releases |
| `edit` | [Microsoft Edit](https://github.com/microsoft/edit) 2.0 |
| `pwsh` | [PowerShell 7](https://github.com/PowerShell/PowerShell), in the `-pwsh` tags |

More tools will be added the same way. Every download is pinned by version and SHA-256, and every image ships the licences of what it contains. A daily workflow opens a pull request when a pinned tool has a new release.

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
