#!/usr/bin/env bash
# record-mxe-info.sh: record what an MXE tree contains, for the libarchive build manifests.
#
#   record-mxe-info.sh <mxe-dir> "<mxe packages>"
#
# Writes <mxe-dir>/mxe-info.json (the MXE commit, the GCC, binutils and mingw-w64 versions, and the
# version of each requested package), copies each package's licence files from its downloaded source
# tarball to <mxe-dir>/licenses/<package>/, and keeps the LGPL libiconv tarball in <mxe-dir>/sources/.
# Run it after MXE has built, while <mxe-dir>/pkg still holds the downloads.
set -euo pipefail

mxe_dir=${1:?usage: record-mxe-info.sh <mxe-dir> "<packages>"}
read -r -a packages <<<"${2:?usage: record-mxe-info.sh <mxe-dir> \"<packages>\"}"

cd "${mxe_dir}"

# The version MXE declares for a package: "$(PKG)_VERSION  := 1.2.3" in its .mk file.
# shellcheck disable=SC2016 # $(PKG) is Make syntax in the .mk files, not a shell expansion.
pkg_version() {
    local mk=$1
    sed -n 's/^\$(PKG)_VERSION[[:space:]]*:=[[:space:]]*//p' "${mk}" | head -n 1
}

gcc_id=$(sed -n 's/^MXE_GCC_ID[[:space:]]*:=[[:space:]]*//p' Makefile | head -n 1)
gcc_mk="plugins/${gcc_id}/gcc.mk"
[[ -f ${gcc_mk} ]] || { echo "error: cannot find ${gcc_mk} for MXE_GCC_ID=${gcc_id}" >&2; exit 1; }

# Packages that end up in libarchive's binaries: the requested ones (cc is the toolchain) plus the
# toolchain parts that are linked in (libgcc and the mingw-w64 runtime and winpthreads).
declare -A versions=()
declare -A mk_files=()
for pkg in "${packages[@]}"; do
    [[ ${pkg} == cc ]] && continue
    [[ -f src/${pkg}.mk ]] || { echo "error: MXE has no package ${pkg}" >&2; exit 1; }
    mk_files[${pkg}]=src/${pkg}.mk
done
mk_files[gcc]=${gcc_mk}
mk_files[mingw-w64]=src/mingw-w64.mk
mk_files[binutils]=src/binutils.mk

json_packages='{}'
for pkg in "${!mk_files[@]}"; do
    versions[${pkg}]=$(pkg_version "${mk_files[${pkg}]}")
    [[ -n ${versions[${pkg}]} ]] || { echo "error: no version in ${mk_files[${pkg}]}" >&2; exit 1; }
    json_packages=$(jq --arg k "${pkg}" --arg v "${versions[${pkg}]}" '. + {($k): $v}' <<<"${json_packages}")
done

# Licence files: top-level COPYING*, LICENSE*, LICENCE*, COPYRIGHT* and NOTICE* entries of each
# source tarball, plus the mingw-w64 runtime and winpthreads licences, which sit deeper.
mkdir -p licenses sources
for pkg in "${!mk_files[@]}"; do
    [[ ${pkg} == binutils ]] && continue   # a build tool, not linked into the binaries
    ver=${versions[${pkg}]}
    tarball=$(find pkg -maxdepth 1 -type f \( -name "${pkg}-${ver}.*" -o -name "${pkg}-v${ver}.*" \) | head -n 1)
    [[ -n ${tarball} ]] || { echo "error: no source tarball for ${pkg} ${ver} in ${mxe_dir}/pkg" >&2; exit 1; }
    mapfile -t members < <(tar -tf "${tarball}" | grep -iE '^[^/]+/((COPYING|LICEN[CS]E|COPYRIGHT|NOTICE)[^/]*)$|^[^/]+/mingw-w64-libraries/winpthreads/COPYING$|^[^/]+/COPYING\.MinGW-w64(-runtime)?/[^/]+$' || true)
    [[ ${#members[@]} -gt 0 ]] || { echo "error: no licence files found in ${tarball}" >&2; exit 1; }
    dest="licenses/${pkg}"
    mkdir -p "${dest}"
    tmp=$(mktemp -d)
    tar -xf "${tarball}" -C "${tmp}" "${members[@]}"
    for member in "${members[@]}"; do
        # Flatten "pkg-1.2/sub/dir/COPYING" to "sub_dir_COPYING" (or just "COPYING" at the top).
        rel=${member#*/}
        cp "${tmp}/${member}" "${dest}/${rel//\//_}"
    done
    rm -rf "${tmp}"
    echo "licences: ${pkg} ${ver}: ${#members[@]} file(s) from $(basename "${tarball}")"
    if [[ ${pkg} == libiconv ]]; then
        cp "${tarball}" sources/
    fi
done

jq -n \
    --arg commit "$(git rev-parse HEAD)" \
    --arg commit_date "$(git log -1 --format=%cI)" \
    --arg gcc_id "${gcc_id}" \
    --arg targets "x86_64-w64-mingw32.static x86_64-w64-mingw32.shared" \
    --argjson packages "${json_packages}" \
    '{mxe_commit: $commit, mxe_commit_date: $commit_date, gcc_plugin: $gcc_id,
      targets: ($targets | split(" ")), packages: $packages}' >mxe-info.json

cat mxe-info.json
