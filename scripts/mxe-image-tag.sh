#!/usr/bin/env bash
# mxe-image-tag.sh: print the GHCR reference of the MXE build image.
#
#   scripts/mxe-image-tag.sh            ghcr.io/<owner>/mxe-libarchive:latest
#   scripts/mxe-image-tag.sh <commit>   ghcr.io/<owner>/mxe-libarchive:sha-<full commit SHA>
#
# mxe-image.yml tags every image it builds sha-<the commit it was built from>, and also latest when it
# builds the default branch. A commit can be any name git resolves (a short SHA, a branch, a tag); it is
# resolved to the full SHA in this checkout, so it must have been fetched. The owner is
# $GITHUB_REPOSITORY_OWNER, or zippy1981 outside Actions. GHCR names are lower case.
set -euo pipefail
owner=${GITHUB_REPOSITORY_OWNER:-zippy1981}
repo="ghcr.io/${owner,,}/mxe-libarchive"
if [[ $# -eq 0 || -z $1 ]]; then
    echo "${repo}:latest"
    exit 0
fi
if ! sha=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --verify --quiet "$1^{commit}"); then
    echo "mxe-image-tag.sh: '$1' is not a commit in this checkout" >&2
    exit 1
fi
echo "${repo}:sha-${sha}"
