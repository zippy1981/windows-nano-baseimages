#!/usr/bin/env bash
# build-libarchive.sh: cross-compile a libarchive release for 64-bit Windows with MXE, validate the
# binaries, and package them.
#
#   scripts/build-libarchive.sh [options] <version> [output-dir]
#
#   <version>      An upstream release, X.Y.Z (no leading v), for example 3.8.11.
#   [output-dir]   Where the zips go. Defaults to ./out. Earlier packages and work/ are replaced.
#
# Options:
#   --source-url <url>      Build from this tarball instead of the GitHub release (for testing). It
#                           needs --sha256, or --signature-url for a detached signature.
#   --signature-url <url>   The detached OpenPGP signature for --source-url.
#   --sha256 <hex>          The SHA-256 of --source-url.
#   --jobs <n>              Parallel compile jobs. Defaults to the number of CPUs.
#   -h, --help              Show this help.
#
# Environment:
#   MXE_DIR           The MXE tree (default /opt/mxe, as in the mxe-libarchive image).
#   SOURCE_DATE_EPOCH If set, the build date recorded in the manifests.
#
# Produces, for version X.Y.Z:
#   libarchive-X.Y.Z-windows-x64-static.zip        executables, static libraries, headers, licences
#   libarchive-X.Y.Z-windows-x64-shared.zip        executables, DLLs, import libraries, headers, licences
#   libarchive-X.Y.Z-windows-x64-static-tools.zip  the static executables and their licences only
#   libarchive-X.Y.Z-windows-x64-manifest.json     the static build's manifest, for release notes
#   SHA256SUMS                                     hashes of the files above
#
# Release tarballs are checked against keys/libarchive-release-keys.asc with gpgv. The script fails if
# a feature it asks for is not found by CMake, if an expected executable is missing, or if a static
# executable imports a DLL that is not part of Windows.
set -euo pipefail

usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; }
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mxe_dir=${MXE_DIR:-/opt/mxe}
jobs=$(nproc)
source_url=
signature_url=
source_sha256=

positional=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-url) source_url=${2:?--source-url needs a value}; shift 2 ;;
        --signature-url) signature_url=${2:?--signature-url needs a value}; shift 2 ;;
        --sha256) source_sha256=${2:?--sha256 needs a value}; shift 2 ;;
        --jobs) jobs=${2:?--jobs needs a value}; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        --) shift; positional+=("$@"); break ;;
        -*) die "unknown option $1 (see --help)" ;;
        *) positional+=("$1"); shift ;;
    esac
done
[[ ${#positional[@]} -ge 1 && ${#positional[@]} -le 2 ]] || { usage >&2; exit 2; }

version=${positional[0]}
out_dir=${positional[1]:-out}
[[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '${version}'"
[[ ${jobs} =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
if [[ -n ${source_url} && -z ${signature_url} && -z ${source_sha256} ]]; then
    die "--source-url needs --sha256 or --signature-url, so the tarball can be verified"
fi
[[ -z ${source_sha256} || ${source_sha256} =~ ^[0-9a-fA-F]{64}$ ]] || die "--sha256 must be 64 hex digits"

static_target=x86_64-w64-mingw32.static
shared_target=x86_64-w64-mingw32.shared
for tool in "${static_target}-cmake" "${shared_target}-cmake" "${static_target}-objdump" "${static_target}-gcc"; do
    [[ -x ${mxe_dir}/usr/bin/${tool} ]] || die "${mxe_dir}/usr/bin/${tool} not found; set MXE_DIR to an MXE tree with both targets"
done
for tool in curl gpg gpgv jq zip file sha256sum xz tar; do
    command -v "${tool}" >/dev/null || die "${tool} is required"
done
mxe_info=${mxe_dir}/mxe-info.json
[[ -f ${mxe_info} ]] || die "${mxe_info} not found (the mxe-libarchive image writes it)"

name=libarchive-${version}
mkdir -p "${out_dir}"
out_dir=$(cd "${out_dir}" && pwd)
work=${out_dir}/work
# Remove only what an earlier run of this script left, never anything else in the directory.
rm -rf "${work}"
rm -f "${out_dir}"/libarchive-*-windows-x64-*.zip "${out_dir}"/libarchive-*-windows-x64-manifest.json "${out_dir}/SHA256SUMS"
mkdir -p "${work}"

# --- Source ------------------------------------------------------------------------------------------

default_url=https://github.com/libarchive/libarchive/releases/download/v${version}/${name}.tar.xz
if [[ -z ${source_url} ]]; then
    source_url=${default_url}
    signature_url=${default_url}.asc
fi
tarball=${work}/$(basename "${source_url%%\?*}")

download() {
    local url=$1 dest=$2
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 --max-time 600 \
        --output "${dest}" "${url}" || die "download failed: ${url}"
}

log "Downloading ${source_url}"
download "${source_url}" "${tarball}"
actual_sha256=$(sha256sum "${tarball}" | cut -d' ' -f1)
log "SHA-256 ${actual_sha256}"

signature_fpr=
if [[ -n ${source_sha256} ]]; then
    [[ ${actual_sha256,,} == "${source_sha256,,}" ]] || die "SHA-256 mismatch: expected ${source_sha256}, got ${actual_sha256}"
fi
if [[ -n ${signature_url} ]]; then
    log "Verifying the OpenPGP signature ${signature_url}"
    download "${signature_url}" "${tarball}.asc"
    keyring=${work}/libarchive-release-keys.gpg
    gpg --batch --quiet --dearmor <"${repo_root}/keys/libarchive-release-keys.asc" >"${keyring}"
    status=$(gpgv --keyring "${keyring}" --status-fd 1 "${tarball}.asc" "${tarball}" 2>"${work}/gpgv.log") \
        || { cat "${work}/gpgv.log" >&2; die "signature check failed for ${tarball}"; }
    signature_fpr=$(awk '$2 == "VALIDSIG" {print $3; exit}' <<<"${status}")
    [[ -n ${signature_fpr} ]] || { cat "${work}/gpgv.log" >&2; die "gpgv reported no valid signature"; }
    log "Good signature from ${signature_fpr}"
fi

log "Checking and extracting the tarball"
tar -tf "${tarball}" >"${work}/tar-list.txt" || die "${tarball} is not a readable tar archive"
top_dirs=$(cut -d/ -f1 "${work}/tar-list.txt" | sort -u)
[[ ${top_dirs} == "${name}" ]] || die "expected the tarball to contain only ${name}/, found: ${top_dirs//$'\n'/ }"
tar -xf "${tarball}" -C "${work}"
src=${work}/${name}
header_version=$(sed -n 's/^#define ARCHIVE_VERSION_ONLY_STRING "\(.*\)"$/\1/p' "${src}/libarchive/archive.h")
[[ ${header_version} == "${version}" ]] || die "archive.h says version '${header_version}', not ${version}"

# --- Feature matrix ----------------------------------------------------------------------------------

# Options this release really has (OPTION(...) in its CMakeLists.txt). Asking for one it lacks is an error.
mapfile -t release_options < <(grep -oE '^[[:space:]]*(OPTION|option)\([A-Za-z0-9_]+' "${src}/CMakeLists.txt" | sed -E 's/.*\(//' | sort -u)
has_option() { printf '%s\n' "${release_options[@]}" | grep -qx "$1"; }

# External libraries we link. Archive formats (tar, cpio, zip, 7-Zip, RAR and RAR5 reading, ISO9660,
# XAR, WARC, CAB, LHA, ar, mtree, shar) are built in; they have no CMake switches.
want_on=(ENABLE_ZLIB ENABLE_BZip2 ENABLE_LZMA ENABLE_LZ4 ENABLE_ZSTD ENABLE_OPENSSL ENABLE_CNG ENABLE_LIBXML2
    ENABLE_ICONV ENABLE_PCRE2POSIX ENABLE_LIBB2 ENABLE_TAR ENABLE_CPIO ENABLE_CAT ENABLE_UNZIP ENABLE_MD)
# Left out on purpose (docs/adr/0004-libarchive-feature-set.md): LZO is GPL-2.0, mbedTLS and Nettle
# duplicate OpenSSL, PCRE (1) is superseded by PCRE2, Expat is redundant with libxml2, ACLs and extended
# attributes are POSIX features, and the tests need Windows to run.
want_off=(ENABLE_LZO ENABLE_MBEDTLS ENABLE_NETTLE ENABLE_PCREPOSIX ENABLE_EXPAT ENABLE_BSDXML ENABLE_ACL
    ENABLE_XATTR ENABLE_TEST ENABLE_COVERAGE ENABLE_WERROR ENABLE_CLANG_TIDY)

# config.h defines that must come out set; each is checked after configuring.
required_defines=(HAVE_ZLIB_H HAVE_LIBZ HAVE_BZLIB_H HAVE_LIBBZ2 HAVE_LZMA_H HAVE_LIBLZMA HAVE_LZ4_H HAVE_LIBLZ4
    HAVE_ZSTD_H HAVE_LIBZSTD HAVE_OPENSSL_EVP_H HAVE_LIBCRYPTO HAVE_LIBXML2 HAVE_LIBXML_XMLREADER_H HAVE_ICONV
    HAVE_PCRE2POSIX_H HAVE_BCRYPT_H)
# Reported, not required: libb2 is not in MXE, so libarchive uses its bundled BLAKE2.
optional_defines=(HAVE_LIBB2 HAVE_BLAKE2_H HAVE_LIBXMLLITE HAVE_LIBEXPAT HAVE_LZO_LZOCONF_H)

common_args=(-DCMAKE_BUILD_TYPE=Release -DENABLE_INSTALL=ON)
for opt in "${want_on[@]}"; do
    if has_option "${opt}"; then common_args+=("-D${opt}=ON"); else log "note: ${opt} is not an option in ${version}"; fi
done
for opt in "${want_off[@]}"; do
    has_option "${opt}" && common_args+=("-D${opt}=OFF")
done
# Older releases have no bsdunzip.
expected_tools=(bsdtar bsdcpio bsdcat)
[[ -d ${src}/unzip ]] && has_option ENABLE_UNZIP && expected_tools+=(bsdunzip)

# Static links of OpenSSL and libxml2 need these after them on the link line; the standard libraries
# come last, so they resolve what the static archives leave open.
static_std_libs="-liconv -llzma -lz -lbcrypt -lcrypt32 -lws2_32 -luser32 -ladvapi32 -lshell32 -lole32 -lkernel32"
static_args=(-DBUILD_SHARED_LIBS=OFF "-DCMAKE_C_STANDARD_LIBRARIES=${static_std_libs}")
shared_args=(-DBUILD_SHARED_LIBS=ON)
for tool in TAR CPIO CAT UNZIP; do
    has_option "ENABLE_${tool}_SHARED" || continue
    static_args+=("-DENABLE_${tool}_SHARED=OFF")
    shared_args+=("-DENABLE_${tool}_SHARED=ON")
done

# --- Build -------------------------------------------------------------------------------------------

# DLLs every Windows (including Nano Server) provides. Anything else a static tool imports is a failure.
system_dll_re='^(kernel32|kernelbase|ntdll|advapi32|bcrypt|crypt32|user32|ws2_32|msvcrt|ucrtbase|shell32|ole32|oleaut32|secur32|xmllite|api-ms-win-[a-z0-9-]+)\.dll$'

imports_of() {
    "${mxe_dir}/usr/bin/${static_target}-objdump" -p "$1" | sed -n 's/^[[:space:]]*DLL Name: //p' | tr -d '\r'
}

check_pe() {
    local exe=$1 desc
    desc=$(file -b "${exe}")
    [[ ${desc} == "PE32+ executable"*"x86-64"* ]] || die "$(basename "${exe}") is not a 64-bit PE file: ${desc}"
}

declare -A config_args=()
build_variant() {
    local variant=$1 target=$2
    shift 2
    local build=${work}/build-${variant} stage=${work}/stage-${variant}
    local args=("${common_args[@]}" "$@" "-DCMAKE_INSTALL_PREFIX=${stage}")
    config_args[${variant}]="${target}-cmake ${args[*]}"
    log "Configuring the ${variant} build"
    "${mxe_dir}/usr/bin/${target}-cmake" -S "${src}" -B "${build}" "${args[@]}" >"${work}/configure-${variant}.log" 2>&1 \
        || { tail -n 60 "${work}/configure-${variant}.log" >&2; die "CMake configure failed for ${variant}"; }

    local missing=() define
    for define in "${required_defines[@]}"; do
        grep -qE "^#define ${define}( |$)" "${build}/config.h" || missing+=("${define}")
    done
    [[ ${#missing[@]} -eq 0 ]] || { tail -n 80 "${work}/configure-${variant}.log" >&2; die "${variant}: features not found by CMake: ${missing[*]}"; }

    log "Building the ${variant} variant with ${jobs} jobs"
    cmake --build "${build}" --parallel "${jobs}" >"${work}/build-${variant}.log" 2>&1 \
        || { tail -n 60 "${work}/build-${variant}.log" >&2; die "build failed for ${variant}"; }
    cmake --install "${build}" >"${work}/install-${variant}.log" 2>&1 \
        || { tail -n 30 "${work}/install-${variant}.log" >&2; die "install failed for ${variant}"; }

    local tool
    for tool in "${expected_tools[@]}"; do
        [[ -f ${stage}/bin/${tool}.exe ]] || die "${variant}: ${tool}.exe was not built"
        check_pe "${stage}/bin/${tool}.exe"
    done
}

build_variant static "${static_target}" "${static_args[@]}"
build_variant shared "${shared_target}" "${shared_args[@]}"

# --- Validate ----------------------------------------------------------------------------------------

log "Checking the static executables' imports"
static_stage=${work}/stage-static
for tool in "${expected_tools[@]}"; do
    exe=${static_stage}/bin/${tool}.exe
    while read -r dll; do
        [[ -z ${dll} ]] && continue
        [[ ${dll,,} =~ ${system_dll_re} ]] || die "static ${tool}.exe imports ${dll}, which is not a Windows system DLL"
    done < <(imports_of "${exe}")
    log "  ${tool}.exe imports: $(imports_of "${exe}" | tr '\n' ' ')"
done
[[ -f ${static_stage}/lib/libarchive.a ]] || die "static: libarchive.a was not installed"

log "Collecting the shared executables' DLLs"
shared_stage=${work}/stage-shared
shared_target_dir=${mxe_dir}/usr/${shared_target}
dll_search=("${shared_stage}/bin" "${shared_target_dir}/bin" "${shared_target_dir}/lib")
while IFS= read -r dir; do dll_search+=("${dir}"); done < <(find "${mxe_dir}/usr/lib/gcc/${shared_target}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
find_dll() {
    local dll=$1 dir hit
    for dir in "${dll_search[@]}"; do
        hit=$(find "${dir}" -maxdepth 1 -type f -iname "${dll}" -print -quit 2>/dev/null)
        [[ -n ${hit} ]] && { echo "${hit}"; return 0; }
    done
    return 1
}
declare -A shared_dlls=()
queue=()
for tool in "${expected_tools[@]}"; do queue+=("${shared_stage}/bin/${tool}.exe"); done
while [[ ${#queue[@]} -gt 0 ]]; do
    pe=${queue[0]}
    queue=("${queue[@]:1}")
    while read -r dll; do
        [[ -z ${dll} || ${dll,,} =~ ${system_dll_re} ]] && continue
        [[ -n ${shared_dlls[${dll,,}]:-} ]] && continue
        path=$(find_dll "${dll}") || die "shared: $(basename "${pe}") needs ${dll}, which is not in the MXE tree"
        check_pe "${path}"
        shared_dlls[${dll,,}]=${path}
        queue+=("${path}")
    done < <(imports_of "${pe}")
done
[[ -n ${shared_dlls[libarchive.dll]:-} || -n ${shared_dlls[libarchive-13.dll]:-} ]] \
    || log "note: the shared tools do not import a libarchive DLL (ENABLE_*_SHARED missing in ${version}?)"
log "  shared DLLs: $(for p in "${shared_dlls[@]}"; do basename "${p}"; done | sort | tr '\n' ' ')"

# --- Manifest ----------------------------------------------------------------------------------------

build_date=$(date -u ${SOURCE_DATE_EPOCH:+-d "@${SOURCE_DATE_EPOCH}"} +%Y-%m-%dT%H:%M:%SZ)
gcc_version=$("${mxe_dir}/usr/bin/${static_target}-gcc" -dumpversion)
cmake_version=$(cmake --version | head -n 1 | awk '{print $3}')

features_json() {
    local build=$1 define on=() off=()
    for define in "${required_defines[@]}" "${optional_defines[@]}"; do
        if grep -qE "^#define ${define}( |$)" "${build}/config.h"; then on+=("${define}"); else off+=("${define}"); fi
    done
    local crypto
    crypto=$(grep -oE '^#define ARCHIVE_CRYPTO_[A-Z0-9_]+' "${build}/config.h" | awk '{print $2}' | sort -u || true)
    jq -n --args '{config_h_set: $ARGS.positional}' "${on[@]}" \
        | jq --args '. + {config_h_unset: $ARGS.positional}' "${off[@]}" \
        | jq --arg c "${crypto}" '. + {crypto: ($c | split("\n") | map(select(length > 0)))}'
}

imports_json() {
    local stage=$1 tool obj='{}'
    for tool in "${expected_tools[@]}"; do
        obj=$(jq --arg t "${tool}.exe" --arg i "$(imports_of "${stage}/bin/${tool}.exe")" \
            '. + {($t): ($i | split("\n") | map(select(length > 0)))}' <<<"${obj}")
    done
    echo "${obj}"
}

write_manifest() {
    local variant=$1 target=$2 dest=$3
    local build=${work}/build-${variant}
    jq -n \
        --arg version "${version}" \
        --arg source_url "${source_url}" \
        --arg source_sha256 "${actual_sha256}" \
        --arg signature_fpr "${signature_fpr}" \
        --arg target "${target}" \
        --arg linkage "${variant}" \
        --arg build_date "${build_date}" \
        --arg gcc "${gcc_version}" \
        --arg cmake "${cmake_version}" \
        --arg configure "${config_args[${variant}]}" \
        --argjson features "$(features_json "${build}")" \
        --argjson imports "$(imports_json "${work}/stage-${variant}")" \
        --argjson mxe "$(cat "${mxe_info}")" \
        --arg tools "${expected_tools[*]}" \
        '{
          libarchive_version: $version,
          source: {url: $source_url, sha256: $source_sha256, signed_by: (if $signature_fpr == "" then null else $signature_fpr end)},
          target: $target,
          linkage: $linkage,
          tools: ($tools | split(" ") | map(. + ".exe")),
          built_in_formats: ["7zip", "ar", "cab", "cpio", "iso9660", "lha", "mtree", "rar (read)", "rar5 (read)", "raw", "shar", "tar", "warc", "xar", "zip"],
          features: $features,
          imports: $imports,
          dependencies: $mxe.packages,
          toolchain: {mxe_commit: $mxe.mxe_commit, mxe_commit_date: $mxe.mxe_commit_date, gcc: $gcc, cmake: $cmake},
          build_date: $build_date,
          cmake_configure: $configure
        }' >"${dest}/manifest.json"
    jq -r '
        "libarchive \(.libarchive_version) for Windows x64 (\(.linkage))",
        "",
        "Source:      \(.source.url)",
        "SHA-256:     \(.source.sha256)",
        "Signed by:   \(.source.signed_by // "not signature-checked")",
        "Target:      \(.target)",
        "Tools:       \(.tools | join(", "))",
        "Built date:  \(.build_date)",
        "MXE commit:  \(.toolchain.mxe_commit) (\(.toolchain.mxe_commit_date))",
        "GCC:         \(.toolchain.gcc)",
        "",
        "Built-in formats: \(.built_in_formats | join(", "))",
        "Features found (config.h): \(.features.config_h_set | join(" "))",
        "Not found:                 \(.features.config_h_unset | join(" "))",
        "Crypto:                    \(.features.crypto | join(" "))",
        "",
        "Dependencies:",
        (.dependencies | to_entries | sort_by(.key)[] | "  \(.key) \(.value)"),
        "",
        "Imports:",
        (.imports | to_entries[] | "  \(.key): \(.value | join(" "))"),
        "",
        "CMake: \(.cmake_configure)"' "${dest}/manifest.json" >"${dest}/MANIFEST.txt"
}

# Licences for everything linked in, and the source of the one LGPL library (libiconv).
add_licences() {
    local dest=$1
    mkdir -p "${dest}/licenses/libarchive" "${dest}/sources"
    cp "${src}/COPYING" "${dest}/licenses/libarchive/COPYING"
    local pkg
    for pkg in zlib bzip2 xz lz4 zstd openssl libxml2 libiconv pcre2 gcc mingw-w64; do
        [[ -d ${mxe_dir}/licenses/${pkg} ]] || die "no licences for ${pkg} in ${mxe_dir}/licenses"
        cp -r "${mxe_dir}/licenses/${pkg}" "${dest}/licenses/${pkg}"
    done
    cp "${mxe_dir}"/sources/libiconv-*.tar.* "${dest}/sources/" || die "no libiconv source tarball in ${mxe_dir}/sources"
    cat >"${dest}/licenses/README.txt" <<EOF
libarchive ${version} is BSD-2-Clause (licenses/libarchive/COPYING).

These binaries also contain code from the libraries in this folder, each under its own licence: zlib,
bzip2, xz (liblzma), lz4, zstd (used under its BSD licence), OpenSSL (Apache-2.0), libxml2 (MIT),
PCRE2 (BSD-3-Clause), the GCC runtime library (GPL-3.0 with the GCC Runtime Library Exception) and the
mingw-w64 runtime and winpthreads.

libiconv is LGPL-2.1-or-later. Its unmodified source is in sources/. The build scripts that produced
these binaries, from libarchive's public source, are at
https://github.com/zippy1981/windows-nano-baseimages (scripts/build-libarchive.sh and mxe/), so the
binaries can be rebuilt against a modified libiconv.
EOF
}

# --- Package -----------------------------------------------------------------------------------------

pkg_root=${work}/packages
mkdir -p "${pkg_root}"
zip_dir() {
    local dir=$1 zipfile=$2
    (cd "$(dirname "${dir}")" && find "$(basename "${dir}")" -exec touch -h -d "${build_date}" {} + && zip -q -X -r -9 "${zipfile}" "$(basename "${dir}")")
}

static_name=${name}-windows-x64-static
shared_name=${name}-windows-x64-shared
tools_name=${name}-windows-x64-static-tools

log "Packaging ${static_name}.zip"
d=${pkg_root}/${static_name}
mkdir -p "${d}/bin" "${d}/lib"
cp -r "${static_stage}/include" "${d}/include"
cp "${static_stage}"/bin/*.exe "${d}/bin/"
cp "${static_stage}/lib/libarchive.a" "${d}/lib/"
[[ -d ${static_stage}/lib/pkgconfig ]] && cp -r "${static_stage}/lib/pkgconfig" "${d}/lib/"
[[ -d ${static_stage}/share ]] && cp -r "${static_stage}/share" "${d}/share"
# The dependencies' static libraries, so libarchive.a can be linked without MXE.
for lib in libz.a libbz2.a liblzma.a liblz4.a libzstd.a libcrypto.a libxml2.a libiconv.a libpcre2-8.a libpcre2-posix.a; do
    cp "${mxe_dir}/usr/${static_target}/lib/${lib}" "${d}/lib/" || die "static: ${lib} not found in MXE"
done
add_licences "${d}"
write_manifest static "${static_target}" "${d}"
zip_dir "${d}" "${out_dir}/${static_name}.zip"

log "Packaging ${shared_name}.zip"
d=${pkg_root}/${shared_name}
mkdir -p "${d}/bin" "${d}/lib"
cp -r "${shared_stage}/include" "${d}/include"
cp "${shared_stage}"/bin/*.exe "${shared_stage}"/bin/*.dll "${d}/bin/"
for path in "${shared_dlls[@]}"; do cp -n "${path}" "${d}/bin/"; done
cp "${shared_stage}"/lib/*.dll.a "${d}/lib/"
[[ -d ${shared_stage}/lib/pkgconfig ]] && cp -r "${shared_stage}/lib/pkgconfig" "${d}/lib/"
[[ -d ${shared_stage}/share ]] && cp -r "${shared_stage}/share" "${d}/share"
add_licences "${d}"
write_manifest shared "${shared_target}" "${d}"
zip_dir "${d}" "${out_dir}/${shared_name}.zip"

log "Packaging ${tools_name}.zip"
d=${pkg_root}/${tools_name}
mkdir -p "${d}"
for tool in "${expected_tools[@]}"; do cp "${static_stage}/bin/${tool}.exe" "${d}/"; done
add_licences "${d}"
cp "${pkg_root}/${static_name}/manifest.json" "${pkg_root}/${static_name}/MANIFEST.txt" "${d}/"
zip_dir "${d}" "${out_dir}/${tools_name}.zip"

cp "${pkg_root}/${static_name}/manifest.json" "${out_dir}/${name}-windows-x64-manifest.json"

# Scope checks: the tools zip has no headers or libraries; each zip has its manifest and licences.
unzip -Z1 "${out_dir}/${tools_name}.zip" | grep -qE '(\.h|\.a|\.lib|\.dll)$' && die "${tools_name}.zip contains headers, libraries or DLLs"
for z in "${static_name}" "${shared_name}" "${tools_name}"; do
    listing=$(unzip -Z1 "${out_dir}/${z}.zip")
    grep -qx "${z}/manifest.json" <<<"${listing}" || die "${z}.zip has no manifest.json"
    grep -qx "${z}/licenses/libarchive/COPYING" <<<"${listing}" || die "${z}.zip has no libarchive licence"
done

(cd "${out_dir}" && sha256sum ./*.zip ./*-manifest.json | sed 's# \./# #' >SHA256SUMS)
log "Done. Packages in ${out_dir}:"
(cd "${out_dir}" && ls -l ./*.zip ./*.json SHA256SUMS) >&2
cat "${pkg_root}/${static_name}/MANIFEST.txt"
