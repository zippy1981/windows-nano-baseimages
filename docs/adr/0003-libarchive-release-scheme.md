# 0003. libarchive release scheme

- Status: Proposed
- Date: 2026-11-06
- Deciders: zippy1981
- Related: [issue #1](https://github.com/zippy1981/windows-nano-baseimages/issues/1), `.github/workflows/build-libarchive.yml`, `scripts/trigger-latest-release.sh`

## Context

The Nano Server images need a small download of the static tools. Developers want the full static and shared packages. Both must name the upstream version they came from.

## Decision

For upstream libarchive `X.Y.Z` we will publish two GitHub releases of this repo:

- `vX.Y.Z`: `libarchive-X.Y.Z-windows-x64-static.zip` and `libarchive-X.Y.Z-windows-x64-shared.zip`.
- `static-X.Y.Z`: `libarchive-X.Y.Z-windows-x64-static-tools.zip`.

Only a `workflow_dispatch` of `build-libarchive.yml` on the default branch publishes, after the Windows smoke tests pass. An existing release has its assets replaced (`gh release upload --clobber`) and its notes rewritten, so a rerun never makes a duplicate. Runs are named `Build libarchive X.Y.Z` and serialised per version. `watch-upstream.yml` dispatches a build when either tag is missing and no run for that version is queued or running.

## Consequences

- The images download `static-X.Y.Z` assets by a predictable URL.
- This repo's `v*` tags mean libarchive versions, so the repo itself can't use `v*` tags for anything else.
- A rebuild of a published version (for example after an MXE bump) replaces its assets in place; the old ones are gone, so record such rebuilds in the release notes.

## Alternatives considered

- One release with all three zips: the images would need the release's other assets to be ignored, and the issue asked for two.
- Suffixes such as `vX.Y.Z-1` for rebuilds: more tags for little benefit, while there is no external consumer.
