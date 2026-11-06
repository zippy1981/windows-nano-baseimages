#!/usr/bin/env bash
# trigger-latest-release.sh: dispatch build-libarchive.yml when libarchive has a release this repo
# hasn't published yet.
#
#   scripts/trigger-latest-release.sh [--dry-run] [--repo owner/name] [--ref branch] [--version X.Y.Z]
#
#   --dry-run          Report what would happen, but don't dispatch.
#   --repo owner/name  The downstream repo. Defaults to $GITHUB_REPOSITORY, then to the git remote.
#   --ref branch       The branch to run build-libarchive.yml on. Defaults to the repo's default branch.
#   --version X.Y.Z    Skip the upstream query and check this version.
#
# It reads the latest published libarchive release from the GitHub API (drafts and prereleases are
# never "latest"), then checks this repo for the releases vX.Y.Z and static-X.Y.Z. If both exist it
# does nothing. If either is missing, and no build-libarchive.yml run for X.Y.Z is queued or running,
# it dispatches one.
#
# Needs a token in GH_TOKEN or GITHUB_TOKEN with contents: read and actions: write on the repo (the
# workflow's GITHUB_TOKEN is enough). Without a token, --dry-run still works within the anonymous rate
# limit. Exits 0 when up to date or dispatched, 1 on an error.
set -euo pipefail

upstream=libarchive/libarchive
workflow=build-libarchive.yml
api_root=${GITHUB_API_URL:-https://api.github.com}
token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
dry_run=false
repo=${GITHUB_REPOSITORY:-}
ref=
version=

log() { echo "$*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) dry_run=true; shift ;;
        --repo) repo=${2:?--repo needs a value}; shift 2 ;;
        --ref) ref=${2:?--ref needs a value}; shift 2 ;;
        --version) version=${2:?--version needs a value}; shift 2 ;;
        -h | --help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
        *) die "unknown argument $1 (see --help)" ;;
    esac
done

if [[ -z ${repo} ]]; then
    remote=$(git config --get remote.origin.url 2>/dev/null || true)
    repo=$(sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##' <<<"${remote}")
fi
[[ ${repo} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "cannot tell the repo; pass --repo owner/name"
[[ -n ${token} || ${dry_run} == true ]] || die "set GH_TOKEN or GITHUB_TOKEN (or use --dry-run)"
for tool in curl jq; do command -v "${tool}" >/dev/null || die "${tool} is required"; done

body_file=$(mktemp)
headers_file=$(mktemp)
trap 'rm -f "${body_file}" "${headers_file}"' EXIT

# api METHOD PATH [JSON]: call the GitHub REST API. Sets $status and leaves the body in $body_file.
# Retries network errors, 5xx, and rate limiting (429, or 403 with x-ratelimit-remaining: 0) a few
# times, waiting for Retry-After or the rate-limit reset, at most 5 minutes each.
api() {
    local method=$1 path=$2 data=${3:-} attempt wait remaining reset
    local args=(--silent --show-error --location --request "${method}" --output "${body_file}"
        --dump-header "${headers_file}" --write-out '%{http_code}' --connect-timeout 20 --max-time 60
        --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28')
    [[ -n ${token} ]] && args+=(--header "Authorization: Bearer ${token}")
    [[ -n ${data} ]] && args+=(--header 'Content-Type: application/json' --data "${data}")
    for attempt in 1 2 3 4 5; do
        status=$(curl "${args[@]}" "${api_root}${path}" 2>/dev/null) || status=000
        remaining=$(awk 'tolower($1) == "x-ratelimit-remaining:" {print $2}' "${headers_file}" 2>/dev/null | tr -d '\r')
        if [[ ${status} == 429 || (${status} == 403 && ${remaining} == 0) ]]; then
            wait=$(awk 'tolower($1) == "retry-after:" {print $2}' "${headers_file}" | tr -d '\r')
            if [[ -z ${wait} ]]; then
                reset=$(awk 'tolower($1) == "x-ratelimit-reset:" {print $2}' "${headers_file}" | tr -d '\r')
                wait=$(( ${reset:-0} - $(date +%s) + 1 ))
            fi
            (( wait < 1 )) && wait=10
            (( wait > 300 )) && die "rate limited by the GitHub API for ${wait}s on ${path}; try again later"
            log "rate limited on ${path}; waiting ${wait}s (attempt ${attempt}/5)"
            sleep "${wait}"
        elif [[ ${status} == 000 || ${status} == 5* ]]; then
            log "GitHub API ${method} ${path} returned ${status}; retrying (attempt ${attempt}/5)"
            sleep $(( attempt * 5 ))
        else
            return 0
        fi
    done
    die "GitHub API ${method} ${path} still failing after 5 attempts (last status ${status})"
}

# --- Upstream ----------------------------------------------------------------------------------------

if [[ -z ${version} ]]; then
    api GET "/repos/${upstream}/releases/latest"
    [[ ${status} == 200 ]] || die "querying ${upstream}'s latest release returned HTTP ${status}: $(head -c 300 "${body_file}")"
    tag=$(jq -r '.tag_name // empty' "${body_file}")
    draft=$(jq -r '.draft' "${body_file}")
    prerelease=$(jq -r '.prerelease' "${body_file}")
    [[ ${draft} == false && ${prerelease} == false ]] || die "${upstream}'s latest release ${tag} is a draft or prerelease"
    [[ ${tag} =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "unexpected upstream tag '${tag}' (wanted vX.Y.Z)"
    version=${BASH_REMATCH[1]}
fi
[[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '${version}'"
log "Latest upstream libarchive release: ${version}"

# --- Downstream --------------------------------------------------------------------------------------

missing=()
for t in "v${version}" "static-${version}"; do
    api GET "/repos/${repo}/releases/tags/${t}"
    case ${status} in
        200) log "  ${repo} release ${t}: exists" ;;
        404) log "  ${repo} release ${t}: missing"; missing+=("${t}") ;;
        *) die "checking ${repo} release ${t} returned HTTP ${status}: $(head -c 300 "${body_file}")" ;;
    esac
done

if [[ ${#missing[@]} -eq 0 ]]; then
    log "Up to date: ${repo} has v${version} and static-${version}. Skipped."
    exit 0
fi

# A run for this version that is already queued or running will publish it; don't start another.
# build-libarchive.yml names its runs "Build libarchive X.Y.Z".
for s in queued in_progress waiting pending requested; do
    api GET "/repos/${repo}/actions/workflows/${workflow}/runs?status=${s}&per_page=100"
    if [[ ${status} == 404 ]]; then
        log "  ${workflow} is not on ${repo}'s default branch yet, so it has no runs to check"
        break
    fi
    [[ ${status} == 200 ]] || die "listing ${workflow} runs returned HTTP ${status}: $(head -c 300 "${body_file}")"
    run=$(jq -r --arg n "Build libarchive ${version}" '[.workflow_runs[] | select(.display_title == $n)][0].html_url // empty' "${body_file}")
    if [[ -n ${run} ]]; then
        log "A build of ${version} is already ${s}: ${run}. Skipped."
        exit 0
    fi
done

if [[ -z ${ref} ]]; then
    api GET "/repos/${repo}"
    [[ ${status} == 200 ]] || die "reading ${repo} returned HTTP ${status}"
    ref=$(jq -r '.default_branch' "${body_file}")
fi

if [[ ${dry_run} == true ]]; then
    log "Dry run: would dispatch ${workflow} on ${ref} with version=${version} (missing: ${missing[*]})."
    exit 0
fi

payload=$(jq -nc --arg ref "${ref}" --arg v "${version}" '{ref: $ref, inputs: {version: $v}}')
api POST "/repos/${repo}/actions/workflows/${workflow}/dispatches" "${payload}"
[[ ${status} == 204 || ${status} == 200 ]] || die "dispatching ${workflow} returned HTTP ${status}: $(head -c 300 "${body_file}")"
log "Dispatched ${workflow} on ${ref} with version=${version} (missing: ${missing[*]})."
