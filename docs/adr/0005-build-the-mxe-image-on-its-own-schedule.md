# 0005. Build the MXE image on its own schedule

- Status: Proposed
- Date: 2026-11-06
- Deciders: zippy1981
- Supersedes: the image tagging and the `build-libarchive.yml` → `mxe-image.yml` call in [0002](0002-build-mxe-on-hosted-runners-and-cache-in-ghcr.md)
- Superseded in part by: [0011](0011-pull-the-mxe-image-by-the-tree-hash-of-mxe.md), for the image `build-libarchive.yml` pulls by default
- Related: `.github/workflows/mxe-image.yml`, `.github/workflows/build-libarchive.yml`, `scripts/mxe-image-tag.sh`

## Context

ADR 0002 tagged the image by the git tree hash of `mxe/`, and every libarchive build called `mxe-image.yml` first, which built the image if that tag was missing. The tag was a cache key, so MXE was built once per change to `mxe/`. It also meant a build could start an hour of MXE work, and that an unchanged `mxe/` never got Ubuntu's package updates, because the image was never rebuilt.

## Decision

We will build the MXE image in its own workflow, and libarchive builds will only pull it.

- `mxe-image.yml` runs weekly, on a push to `main` that changes `mxe/`, and by hand. It always builds, with `--no-cache`, and pushes `ghcr.io/<owner>/mxe-libarchive:sha-<commit>`. On the default branch it then moves `:latest` to that image, after the toolchain check passes.
- `build-libarchive.yml` pulls `:latest` by default. A manual run can pin the image with `mxe_image_commit`, which `scripts/mxe-image-tag.sh` resolves to `:sha-<full SHA>`.
- The build records the pulled image's digest and its `org.opencontainers.image.revision` label in the run summary and the release notes.

## Consequences

- A libarchive build never builds MXE, and fails with a clear error if the image it needs isn't in GHCR.
- The image gets Ubuntu's security updates weekly. Two images from the same commit can differ in their apt packages; the digest in the release notes says which one built a release.
- A change to `mxe/` reaches libarchive builds only after `mxe-image.yml` on `main` has finished. A branch's Dockerfile change is tried by running `mxe-image.yml` on the branch and pinning that commit.
- GHCR keeps every `sha-` tag. Prune old ones in the package settings if storage matters.

## Alternatives considered

- Keep the tree-hash tag and the call from `build-libarchive.yml`: every build may pay for MXE, and an unchanged image never refreshes.
- Pin to the tree hash on a manual run instead of a commit: a tree hash is harder to find than a commit, and two commits with the same `mxe/` tree would share one moving tag.
