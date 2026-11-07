# windows-nano-baseimages

Production-quality Windows Nano Server base images for ltsc2019, ltsc2022 and ltsc2025. They're light, but usable out of the box.

## Images

| Image | Tags | What's in it |
| --- | --- | --- |
| [`zippy1981/nanoserver-base`](images/nanoserver-base/README.md) | `ltsc2019`, `ltsc2022`, `ltsc2025` | Nano Server with `tar` (libarchive bsdtar), `bsdcpio`, `bsdcat`, `bsdunzip`, `jq` and `edit` first on `PATH` |
| `zippy1981/nanoserver-base` | `ltsc2019-pwsh`, `ltsc2022-pwsh`, `ltsc2025-pwsh` | The same, plus PowerShell 7 |

Each tag also has an immutable `ltsc<ver>[-pwsh]-<os-build>-<sha7>` form ([ADR 0004](docs/adr/0004-images-build-on-self-hosted-runners-and-publish-from-main.md)).

| Tool | Source |
| --- | --- |
| `tar` and the other libarchive tools | Compiled here from [libarchive](https://github.com/libarchive/libarchive) with MXE, on GitHub-hosted Linux runners, and published as this repo's `static-X.Y.Z` releases |
| `curl` | Windows' own `C:\Windows\System32\curl.exe`, which uses Schannel and the Windows certificate store. curl.se's build can't verify HTTPS on Nano Server ([ADR 0003](docs/adr/0003-curl-is-the-windows-curl-with-schannel.md)). |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) releases |
| `edit` | [Microsoft Edit](https://github.com/microsoft/edit) 2.0 |
| `pwsh` | [PowerShell 7](https://github.com/PowerShell/PowerShell), in the `-pwsh` tags |

More tools will be added the same way. Every download is pinned by version and SHA-256, and every image ships the licences of what it contains. A daily workflow opens a pull request when a pinned tool has a new release.

## Status

Work is tracked in [issues](https://github.com/zippy1981/windows-nano-baseimages/issues). Issue #1 is the libarchive build and release system, which the images depend on. Decisions are recorded in [docs/adr](docs/adr/README.md).

## Contributing with Claude Code

`CLAUDE.md` holds the repo's conventions and the shared-host safety rules. `.claude/agents/` has the agents that implement the issues: start with `issue-implementer`. Markdown must pass `npx -y markdownlint-cli --dot '**/*.md'`, and `pre-commit run --all-files` runs it.
