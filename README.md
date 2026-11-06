# windows-nano-baseimages

Production-quality Windows Nano Server base images for ltsc2019, ltsc2022 and ltsc2025. They're light, but usable out of the box.

| Tool | Source |
| --- | --- |
| `tar` and the other libarchive tools | Compiled here from [libarchive](https://github.com/libarchive/libarchive) with MXE, on GitHub-hosted Linux runners, and published as this repo's `static-X.Y.Z` releases |
| `curl` | The official Windows builds from <https://curl.se/windows/> |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) releases |
| `edit` | [Microsoft Edit](https://github.com/microsoft/edit) 2.0 |
| `pwsh` | [PowerShell 7](https://github.com/PowerShell/PowerShell) |

More tools will be added the same way. Every download is pinned by version and SHA-256, and every image ships the licences of what it contains.

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
