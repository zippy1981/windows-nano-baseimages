#!/usr/bin/env bash
# mxe-image-tag.sh: print the GHCR reference of the MXE build image.
#
#   scripts/mxe-image-tag.sh                    ghcr.io/<owner>/mxe-libarchive:tree-<tree hash of mxe/ at HEAD>
#   scripts/mxe-image-tag.sh --tree <commit>    ghcr.io/<owner>/mxe-libarchive:tree-<tree hash of mxe/ at commit>
#   scripts/mxe-image-tag.sh <commit>           ghcr.io/<owner>/mxe-libarchive:sha-<full commit SHA>
#   scripts/mxe-image-tag.sh --latest           ghcr.io/<owner>/mxe-libarchive:latest
#
# mxe-image.yml tags every image it builds sha-<the commit it was built from> and tree-<the git tree hash
# of mxe/ in that commit>, and also latest when it builds the default branch. The tree tag is what
# build-libarchive.yml pulls by default: the newest image built from the mxe/ in its own checkout, which a
# rebase or squash merge doesn't change (docs/adr/0011). A commit can be any name git resolves (a short
# SHA, a branch, a tag); it must have been fetched. The owner is $GITHUB_REPOSITORY_OWNER, or zippy1981
# outside Actions. GHCR names are lower case.
set -euo pipefail
owner=${GITHUB_REPOSITORY_OWNER:-zippy1981}
repo="ghcr.io/${owner,,}/mxe-libarchive"
top="$(dirname "${BASH_SOURCE[0]}")/.."

# Prints the object $1 names; it runs in $(...), so the caller exits when it fails.
resolve() {
    git -C "${top}" rev-parse --verify --quiet "$1" || {
        echo "mxe-image-tag.sh: '${1%%^*}' is not a commit in this checkout" >&2
        return 1
    }
}

case ${1:-} in
    --latest)
        echo "${repo}:latest"
        ;;
    "" | --tree)
        tree=$(resolve "${2:-HEAD}^{commit}:mxe")
        echo "${repo}:tree-${tree}"
        ;;
    -*)
        echo "mxe-image-tag.sh: unknown option '$1'" >&2
        exit 2
        ;;
    *)
        sha=$(resolve "$1^{commit}")
        echo "${repo}:sha-${sha}"
        ;;
esac
