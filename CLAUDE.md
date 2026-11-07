# windows-nano-baseimages

Production-quality Windows Nano Server base images for ltsc2019, ltsc2022 and ltsc2025. They stay light but are usable out of the box: a current `tar.exe` that this repo compiles from [libarchive](https://github.com/libarchive/libarchive), plus downloaded, pinned builds of jq, [Microsoft Edit](https://github.com/microsoft/edit) 2.0 and PowerShell 7 (in the `-pwsh` tags). curl is Windows' own. Other tools will be added the same way.

Issues describe the work (`gh issue list`). Issue #1 is the libarchive build system: an MXE cross-compile environment in a Linux container, plus build, packaging, release and upstream-watch automation. **Linux builds run on GitHub-hosted runners** (`ubuntu-latest`), not on this host: the user decided that after the issue was written, so its persistent self-hosted MXE runner and `Run-MxeRunner.ps1` are optional. Build the MXE image in CI and cache it (for example in GHCR, `ghcr.io/zippy1981/...`), so a libarchive build doesn't rebuild MXE. Hosted jobs time out after 6 hours. `.claude/agents/README.md` says which agent owns what.

## Sources of the tools

- **tar (bsdtar) and the other libarchive tools:** built here with MXE (`x86_64-w64-mingw32.static`), and published as GitHub releases of this repo (`vX.Y.Z` for the full packages, `static-X.Y.Z` for the static tools only). The images download the `static-X.Y.Z` release asset. They never use Windows' own `tar.exe`, which is old on ltsc2019 and ltsc2022 and can't read zstd there.
- **curl:** Windows' own `C:\Windows\System32\curl.exe` (Schannel). curl.se's LibreSSL build can't verify HTTPS on Nano Server, so it isn't shipped (`docs/adr/0003`).
- **jq:** `jq-windows-amd64.exe` from <https://github.com/jqlang/jq/releases>.
- **Microsoft Edit:** `edit-<v>-x86_64-windows.zip` from <https://github.com/microsoft/edit/releases>.
- **PowerShell 7:** `PowerShell-<v>-win-x64.zip` from <https://github.com/PowerShell/PowerShell/releases>.

Pin every download by version **and** SHA-256, and check the hash in the build. Prefer upstream's published checksums, and compute the hash yourself only when upstream has none. Record each pin in one `ENV` block per tool.

## Image conventions

- `ARG WINDOWS_VERSION=2025`, `ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64`, and the last stage is `FROM ${BASE_IMAGE}`. Every image must build and work on 2019, 2022 and 2025. A tool that can't run on one version is left out there and documented, never shipped broken.
- Every Dockerfile starts with a header: `# <image>: <what it is>`, then a `docker build --build-arg ...` example. Every `ARG` has a comment directly above it, saying what it does and showing `--build-arg NAME=<example>` (the `dockerfile-docs` skill).
- Licences: every image carries the licence files of what it ships. For copyleft tools it also carries the corresponding source, or the release tarball, inside the image. Say so in the Dockerfile header.
- Every PowerShell script has `[CmdletBinding()]` and comment-based help with a `.SYNOPSIS`, and passes PSScriptAnalyzer.

## Lessons from windows-nano-demos (the sibling repo)

- Docker passes each `RUN` to `powershell -Command` (or `cmd /S /C`) with **double quotes stripped**. In a PowerShell `RUN`, build strings with single quotes and `+`, and use `${env:NAME}` for variables.
- A path that ends a line with `\` is read as a **line continuation**. Never end a line in a Dockerfile with a path backslash.
- Some release zips use **Deflate64** (the nano port did). Windows PowerShell 5.1's `Expand-Archive` can't decompress it, and `tar.exe` silently writes zero bytes. Unpack with 7-Zip (this repo's bsdtar can't yet, #7), and check that every `.exe` starts with `MZ`.
- Nano Server lacks the VC++ runtime and `icu.dll`. Copy `vcruntime140*.dll` from a Server Core stage that ran `vc_redist`, never from the host.
- libarchive on Windows can't decompress Deflate64 (#7), and silently drops the first ~64 KB of a zip read from a pipe (#8). Never pipe a zip into tar.
- ltsc2019 lacks newer API entry points. A program built against a newer SDK can fail there with `0xC0000139`. Test every tool on all three versions.
- Hyper-V isolated builds default to 1 GB of memory. Build with `--memory 4g`.
- Check what a tool really prints before writing a smoke test. Nano Server has no `where.exe` or `whoami.exe`; use cmd's `%~$PATH:i` and `%USERNAME%`.

## Shared host safety

This repo shares a Windows host with `windows-nano-demos`, whose self-hosted runners (`DEARING-HP-Z-nano*` containers) use the Windows Docker engine.

- Never `docker system prune`, `image prune` or `builder prune`. Remove only containers and images you created, by name (the `safe-docker-cleanup` skill).
- Don't touch the `DEARING-HP-Z-nano*` containers, or images under `zippy1981/` that you didn't build in this session.
- **Don't switch Docker Desktop between Windows and Linux containers.** Switching takes the windows-nano-demos runners offline. Linux work, including MXE, runs on GitHub-hosted `ubuntu-latest` runners, so it never needs this host's engine.
- Don't change host settings, services, firewall, DNS, hosts files or certificate stores without asking. Never read, print or store tokens. Runner registration tokens are passed by the user at run time.

## Workflow

- The user asked for this setup to be committed directly to `main`. For later work, follow the user's instructions about branches and PRs.
- Markdown must pass `npx -y markdownlint-cli --dot '**/*.md'`. `pre-commit run --all-files` runs it.
- No workflows were copied from windows-nano-demos. Workflows here are written for this repo by `workflow-author`, to `cicd-engineer`'s design.
