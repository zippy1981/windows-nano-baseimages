# 0012. Carry patches on libarchive releases

- Status: Proposed
- Date: 2026-11-10
- Deciders: zippy1981
- Related: [issue #7](https://github.com/zippy1981/windows-nano-baseimages/issues/7), [issue #8](https://github.com/zippy1981/windows-nano-baseimages/issues/8), [0003](0003-libarchive-release-scheme.md), [0004](0004-libarchive-feature-set.md), `scripts/build-libarchive.yaml`, `patches/libarchive/`

## Context

Two upstream libarchive bugs keep this repo's bsdtar from replacing 7-Zip in the images. It has no Deflate64 (zip method 9) decoder, so zips such as nano for Windows fail (#7). On Windows it drops the first ~64 KB of a zip read from a pipe and exits 0 (#8). Neither is fixed in a release. Upstream has an open draft PR for Deflate64 ([libarchive#2806](https://github.com/libarchive/libarchive/pull/2806)), which uses Microsoft's [InflateLib](https://github.com/microsoft/inflatelib) (MIT), and nothing yet for the pipe bug. libarchive's own Windows CI builds have the same bugs (#16).

## Decision

We will build each libarchive release with a short, ordered list of patches from `patches/libarchive/`, listed in `scripts/build-libarchive.yaml`. Each patch:

- Applies with `patch -p1` and no fuzz, or the build fails.
- Has a header saying what it fixes, the issue, and where it came from (an upstream PR, or written here).
- Is recorded with its SHA-256 in every package's manifest, and shipped in `sources/patches/`.
- Is dropped once a release that fixes the bug upstream is built.

The two first patches are a port of libarchive#2806 to 3.8.11 (Deflate64, with InflateLib built from a pinned tag as a static library) and a Windows-only fix that stops the read callbacks seeking a pipe.

## Consequences

- bsdtar extracts Deflate64 zips and piped zips, so the images' smoke tests can drop those expected failures once a patched `static-X.Y.Z` is released and pinned.
- Each new libarchive release needs the patches checked. A patch that no longer applies fails the build, and is ported or dropped.
- The binaries aren't upstream's code exactly; `bsdtar --version` shows `inflatelib/<version>`, and the manifest and `sources/patches/` say what changed.
- **Republishing an existing version:** under [0003](0003-libarchive-release-scheme.md), a rebuild of 3.8.11 replaces the `v3.8.11` and `static-3.8.11` assets. The images pin `static-3.8.11` by SHA-256, so their builds fail until the pin is updated, and the tool-version watcher compares versions, not hashes, so it won't open that PR. Releasing a patched build under the same tag needs the pin bumped by hand at the same time, or a release scheme that distinguishes builds (for example a build suffix), which would supersede 0003.
- The patches should go upstream: #7 by helping #2806 land, #8 as a new issue and PR.

## Alternatives considered

- Wait for upstream: #2806 has been a draft since 2025 and InflateLib is a pre-release. Until then, the images keep 7-Zip for these zips and never pipe a zip into tar.
- zlib's `contrib/infback9` for Deflate64: callback-based, so the streaming zip reader would need restructuring; #2806 already did the equivalent work with an `inflate`-style API.
- Work around #8 in the images (never pipe zips): already the rule, but it leaves a silent data-loss bug in the tool the images ship.
