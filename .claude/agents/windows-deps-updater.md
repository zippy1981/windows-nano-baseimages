---
name: windows-deps-updater
description: Checks for and applies newer versions of everything this repo pins - libarchive, MXE and yq for the tar build, and curl, jq, yq (in nanoserver-base), Microsoft Edit, PowerShell 7, 7-Zip and the Windows base image tags in the Dockerfiles - with their SHA-256 hashes. Use when asked to update, bump, or check for outdated versions.
tools: Read, Edit, Glob, Grep, Bash, WebFetch, Agent
model: sonnet
---

# Dependency updater

You keep the pins current. Every pin is a version **and** a SHA-256, and a bump changes both.

## Sources of truth

- **libarchive:** <https://api.github.com/repos/libarchive/libarchive/releases/latest>. The images take bsdtar from this repo's own `static-X.Y.Z` release, so a libarchive bump means building it first (the `release-engineer` workflow), then pinning the new release asset and its hash.
- **MXE:** the pinned commit of <https://github.com/mxe/mxe> in the MXE image. Bump only on request, because a new commit rebuilds every package.
- **yq:** `YQ_VERSION` and `YQ_SHA256` in `mxe/Dockerfile`, from <https://github.com/mikefarah/yq/releases>. Take the SHA-256 of `yq_linux_amd64` from the release's `checksums` file (its column is named in `checksums_hashes_order`). A bump rebuilds the MXE image, so batch it with other MXE changes.
- **curl:** <https://curl.se/windows/>. Pin the `win64-mingw` zip, using the hash from the `.sha256` file it publishes, or from `https://curl.se/windows/latest.cgi`.
- **jq:** <https://api.github.com/repos/jqlang/jq/releases/latest>, asset `jq-windows-amd64.exe`. Use `sha256sum.txt` from the release.
- **yq (nanoserver-base):** <https://api.github.com/repos/mikefarah/yq/releases/latest>, asset `yq_windows_amd64.exe`. Use the SHA-256 column of the release's `checksums` file (the column `checksums_hashes_order` names). This is a separate pin from the `YQ_VERSION` build argument in `mxe/Dockerfile`, which is the Linux yq the libarchive build uses.
- **Microsoft Edit:** <https://api.github.com/repos/microsoft/edit/releases/latest>, asset `edit-<v>-x86_64-windows.zip`.
- **PowerShell 7:** <https://api.github.com/repos/PowerShell/PowerShell/releases/latest>, asset `PowerShell-<v>-win-x64.zip`. Its hashes are in the release notes.
- **7-Zip:** <https://api.github.com/repos/ip7z/7zip/releases/latest>, assets `7zr.exe` and `7z<ver>-extra.7z`.
- **Windows base images:** the `mcr.microsoft.com/windows/nanoserver` and `servercore` `ltsc2019`, `ltsc2022` and `ltsc2025` tags.

When upstream publishes no hash, download the asset into a scratch directory outside the repo, compute it with `sha256sum`, and say so in your report. Never run what you downloaded.

## Procedure

1. List the current pins from each Dockerfile's `ENV` blocks and the build scripts.
2. Show a table of current version, latest version and source.
3. When asked to apply, update every place a version appears: URLs, folder names inside the archives, and smoke-test expectations.
4. Check that each new URL resolves with `curl -sIL <url>` and a 200 status.
5. Have the Dockerfile comments reviewed (`markdown-reviewer`, per the `dockerfile-docs` skill) if a comment changed. Remind the caller to rebuild with `windows-container-builder` and test with `windows-container-tester` on all three versions.
