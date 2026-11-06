# libarchive for Windows: MXE build, releases and upstream watch

## Goal

Cross-compile any libarchive release for 64-bit Windows from Linux with MXE, test it on Windows and Nano Server, and publish it as `vX.Y.Z` (full static and shared packages) and `static-X.Y.Z` (static tools only), with a daily watcher that dispatches the build for each new upstream release. Done when a `workflow_dispatch` on `main` publishes both releases and the watcher skips a version already published. Tracks zippy1981/windows-nano-baseimages#1.

## Context

- Before this work the repo had only markdown lint, the agents and `scripts/Remove-DockerArtifacts.ps1`. Nothing could be reused for the build.
- `CLAUDE.md` changed issue #1: Linux builds run on GitHub-hosted `ubuntu-latest` runners, the MXE image is built in CI and cached in GHCR, and the self-hosted runner and `Run-MxeRunner.ps1` are optional.
- Upstream, checked on 2026-11-06: libarchive 3.8.11 is the latest release. Its tarballs are signed (`.tar.xz.asc`) by Martin Matuska's key `659C84C0E23EA1FA97E0B58CC040B508D63D2B36`; no SHA-256 file is published. MXE `a6738d9d` (2026-10-30) has GCC 15.3.0, zlib 1.3.2, bzip2 1.0.8, xz 5.8.4, lz4 1.10.0, zstd 1.5.7, OpenSSL 4.1.0, Expat 2.9.0, libxml2 2.15.4, libiconv 1.19 and PCRE2 10.49. It has no mbedTLS or libb2 package.

## Decisions

- Build the MXE image on hosted runners and cache it in GHCR, tagged by the git tree hash of `mxe/`. ADR [0002](../docs/adr/0002-build-mxe-on-hosted-runners-and-cache-in-ghcr.md).
- Release scheme `vX.Y.Z` plus `static-X.Y.Z`, published only from the default branch, assets replaced in place. ADR [0003](../docs/adr/0003-libarchive-release-scheme.md).
- Feature set: every external library MXE provides, except LZO (GPL-2.0), mbedTLS and Nettle (duplicate OpenSSL) and PCRE 1. libxml2 is used for XAR; Expat is built but unused. ADR [0004](../docs/adr/0004-libarchive-feature-set.md).
- Verify release tarballs with `gpgv` against keys committed in `keys/`, because upstream publishes signatures, not hashes.
- Defer the self-hosted runner and `Run-MxeRunner.ps1`, as `CLAUDE.md` allows.

## Plan

### Phase 1: Inspect and plan

- [x] **planning**: this plan. Accept: the file passes markdownlint.
- [x] **adr**: ADRs 0001 to 0004 and the index. Accept: `docs/adr/README.md` lists them.

### Phase 2: MXE build environment

- [x] **mxe-builder**: `mxe/Dockerfile` and `mxe/record-mxe-info.sh`. Accept: `record-mxe-info.sh` passes shellcheck and writes `mxe-info.json`, licences and the libiconv source from an MXE tree.
- [x] **mxe-builder**: the image builds in `mxe-image.yml` and both targets compile a C program. Accept: a green `image` job, and the tag in GHCR. Done: 56 minutes, 1.02 GB compressed.

### Phase 3: Runner management (deferred)

- [ ] **powershell-author**: `Run-MxeRunner.ps1` and a runner entrypoint, only if the user asks for a self-hosted runner.

### Phase 4 and 5: Build and packaging

- [x] **libarchive-builder**: `scripts/build-libarchive.sh`. Accept: shellcheck passes; it rejects a bad version and a missing MXE tree.
- [x] **libarchive-builder**: a test build of 3.8.11. Accept: the `build` job is green and uploads the three zips, the manifest and `SHA256SUMS`. Done: every required feature found; the static tools import only `bcrypt`, `KERNEL32` and `msvcrt`.

### Phase 6 and 7: Workflows

- [x] **release-engineer**: `build-libarchive.yml`, `watch-upstream.yml`, `scripts/trigger-latest-release.sh` and `scripts/Test-LibarchivePackage.ps1`. Accept: `trigger-latest-release.sh --dry-run` reports both releases missing for 3.8.11.
- [x] **release-engineer**: the smoke tests pass on `windows-2022` and `windows-2025`, including Nano Server. Accept: green `smoke-test` jobs. Done: all six jobs, with Nano Server ltsc2022 and ltsc2025.
- [ ] **release-engineer**: after merging to `main`, dispatch 3.8.11, then run the watcher twice. Accept: both releases exist with the named assets; the second watcher run logs "Up to date".
- [x] **workflow-author**: `lint-scripts.yml` (actionlint, shellcheck, PSScriptAnalyzer). Accept: green on the branch.

### Phase 8: Documentation

- [x] **markdown-fixer**: `docs/libarchive-build.md` and the README. Accept: markdownlint passes.

## Risks

- **The MXE build runs past the 6-hour job limit.** It builds two GCC toolchains and a small package set; if it runs long, split the toolchain and the packages into two images.
- **OpenSSL 4 and libarchive disagree.** The build fails loudly on `HAVE_LIBCRYPTO`; fall back to Windows CNG, which libarchive already uses, by dropping OpenSSL in ADR 0004.
- **ltsc2019 can't be tested on hosted runners.** The tools import only system DLLs and the `msvcrt` CRT, which ltsc2019 has. The Nano Server images test them there (CLAUDE.md).
- **The signing key changes.** A new key makes `gpgv` fail loudly; add the key to `keys/` after checking it on libarchive's release page.
- **GHCR visibility.** The first push creates a private package, which this repo's `GITHUB_TOKEN` can pull. Other repos need it made public or granted access.

## Owners

| Agent | Tasks |
| --- | --- |
| `mxe-builder` | `mxe/Dockerfile`, `mxe/record-mxe-info.sh` |
| `libarchive-builder` | `scripts/build-libarchive.sh` |
| `release-engineer` | `build-libarchive.yml`, `watch-upstream.yml`, `trigger-latest-release.sh`, `Test-LibarchivePackage.ps1` |
| `workflow-author` | `mxe-image.yml`, `lint-scripts.yml` |
| `adr` | `docs/adr/` |
| `planning` | this plan |
