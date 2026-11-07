# 0002. Build MXE on hosted runners and cache it in GHCR

- Status: Proposed; image tagging and the build coupling superseded by [0005](0005-build-the-mxe-image-on-its-own-schedule.md)
- Date: 2026-11-06
- Deciders: zippy1981
- Related: [issue #1](https://github.com/zippy1981/windows-nano-baseimages/issues/1), [plan](../../plans/issue-1-libarchive-build.md), `mxe/Dockerfile`, `.github/workflows/mxe-image.yml`

## Context

Issue #1 asked for a persistent self-hosted Linux runner holding MXE. The only host is a Windows machine shared with windows-nano-demos, whose runners stop if Docker Desktop is switched to Linux containers. MXE builds GCC and every dependency from source, which takes hours. Hosted jobs stop at 6 hours.

## Decision

We will build the MXE environment as a Docker image (`mxe/Dockerfile`: Ubuntu 24.04 pinned by digest, MXE pinned to a commit, both `x86_64-w64-mingw32.static` and `.shared` targets) on GitHub-hosted `ubuntu-latest` runners. `mxe-image.yml` pushes it to `ghcr.io/<owner>/mxe-libarchive:mxe-<tree>`, where `<tree>` is the first 16 characters of the git tree hash of `mxe/` (`scripts/mxe-image-tag.sh`), and skips the build when that tag exists. `build-libarchive.yml` calls it first, then runs the build inside the image as the runner's uid. The self-hosted runner and `Run-MxeRunner.ps1` are deferred.

## Consequences

- The shared Windows host is never involved in Linux builds.
- Any committed change to `mxe/` (an MXE bump, a package added) triggers one rebuild of about an hour (the first build took 56 minutes), then every libarchive build reuses the image.
- The GHCR package starts private; this repo's `GITHUB_TOKEN` can pull it. Make it public if other repos need it.
- If MXE outgrows 6 hours, split the image into a toolchain stage and a packages stage (`mxe-builder`).

## Alternatives considered

- A self-hosted runner on the shared host: needs Linux containers there, which takes the windows-nano-demos runners offline.
- `actions/cache` for the MXE tree: limited to 10 GB per repo, and evicted after 7 days unused.
- MXE's prebuilt apt packages: unmaintained, and only for old Ubuntu releases.
- Ubuntu's own mingw-w64 packages: no cross-built zstd, lz4, OpenSSL or libxml2.
