#!/usr/bin/env bash
# mxe-image-tag.sh: print the GHCR reference of the MXE build image for the committed mxe/ folder.
#
#   scripts/mxe-image-tag.sh [owner]
#
# The tag is the git tree hash of mxe/ at HEAD, so any committed change to the Dockerfile or its
# scripts (including the MXE commit pin) names a new image, and an unchanged folder reuses the cached
# one. The owner defaults to $GITHUB_REPOSITORY_OWNER, then to zippy1981. GHCR names are lower case.
set -euo pipefail
owner=${1:-${GITHUB_REPOSITORY_OWNER:-zippy1981}}
tree=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse HEAD:mxe)
echo "ghcr.io/${owner,,}/mxe-libarchive:mxe-${tree:0:16}"
