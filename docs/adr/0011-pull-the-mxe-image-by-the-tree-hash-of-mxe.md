# 0011. Pull the MXE image by the tree hash of mxe/

- Status: Proposed
- Date: 2026-11-10
- Deciders: zippy1981
- Supersedes: the default image `build-libarchive.yml` pulls (`:latest`) in [0005](0005-build-the-mxe-image-on-its-own-schedule.md)
- Related: `.github/workflows/mxe-image.yml`, `.github/workflows/build-libarchive.yml`, `scripts/mxe-image-tag.sh`

## Context

Under ADR 0005, `build-libarchive.yml` pulls `:latest`, which only `mxe-image.yml` on `main` moves. A branch that changes `mxe/` and the build script together, such as adding yq to the image and making the script use it, can't pass its own push builds: they run the new script in the old image, and a push build can't pin `mxe_image_commit`. After the merge, `main`'s push build fails too, until the hour-long image build there finishes. A pin by commit doesn't help either, since a rebase or a squash merge gives the branch new commits with no images.

## Decision

We will tag every MXE image with the git tree hash of `mxe/`, and libarchive builds will pull the tag for the `mxe/` in their own checkout.

- `mxe-image.yml` pushes `sha-<commit>`, then `tree-<git rev-parse <commit>:mxe>`, and on the default branch `:latest`. The tree tag moves to the newest image built from that tree, so the weekly rebuild on `main` still refreshes it.
- `build-libarchive.yml` pulls `tree-<hash>` by default. `mxe_image_commit` still pins `sha-<commit>`. It still never builds MXE, and records the digest and the image's revision label.
- A branch that changes `mxe/` runs `mxe-image.yml` by hand on the branch before its builds pass. A push that changes `mxe/` also runs the test build, so the missing image shows up as a failed check.

## Consequences

- A branch is tested with the image its `mxe/` describes. The tag outlives rebases and squash merges, so the image built on the branch serves `main` straight after the merge, while `main`'s own rebuild runs.
- Branches that don't change `mxe/` share `main`'s tree, so they need no image build.
- A branch's `mxe/` change can move a tree tag before it merges. That tag is only used by checkouts with the same `mxe/`, so `main` is unaffected while its tree differs.
- `:latest` is kept for people who want "whatever `main` last built", but no workflow uses it.

## Alternatives considered

- Keep `:latest` and merge image changes in their own PR first: it works, but every `mxe/` change needs two PRs, and the second can't be tested until the first has merged and built.
- Build the image in `build-libarchive.yml` when its tree tag is missing (ADR 0002): a libarchive build could then spend an hour on MXE, which ADR 0005 moved out on purpose.
