# 0004. libarchive feature set

- Status: Proposed
- Date: 2026-11-06
- Deciders: zippy1981
- Related: [issue #1](https://github.com/zippy1981/windows-nano-baseimages/issues/1), `scripts/build-libarchive.sh`, `mxe/Dockerfile`

## Context

libarchive builds its archive formats in (tar, pax, cpio, zip, 7-Zip, RAR and RAR5 reading, ISO9660, XAR, WARC, CAB, LHA, ar, mtree, shar); they have no CMake switches. External libraries add filters, encryption and XML. libarchive 3.8.11's `CMakeLists.txt` has the `ENABLE_*` options for them. MXE (commit `a6738d9d`) provides zlib, bzip2, xz, lz4, zstd, OpenSSL, Expat, libxml2, libiconv, LZO, Nettle, PCRE and PCRE2, but not mbedTLS or libb2. The binaries ship in images that must carry the licences, and the source of copyleft code.

## Decision

We will turn on, and fail the build if CMake doesn't find: zlib, bzip2, LZMA (xz), LZ4, Zstandard, OpenSSL, Windows CNG, libxml2 (for XAR), iconv (libiconv, which libarchive needs before it uses libxml2) and PCRE2's POSIX regex (for `bsdtar -s`). We will turn off:

- LZO: GPL-2.0, which would make the binaries GPL. libarchive reads and writes lzop through the external `lzop` program instead.
- mbedTLS and Nettle: OpenSSL and CNG cover the same algorithms. mbedTLS isn't in MXE.
- PCRE (1): superseded by PCRE2.
- Expat and bsdxml: libarchive uses one XML library, and prefers libxml2. Expat stays in the image as a fallback.
- ACLs and extended attributes: POSIX features with no Windows implementation in libarchive.
- The test suite: it needs Windows to run. The Windows smoke tests run the tools instead.

libb2 is wanted but missing from MXE, so libarchive uses its bundled BLAKE2. libiconv is LGPL-2.1, so every package ships its source tarball in `sources/`.

## Consequences

- `scripts/build-libarchive.sh` checks `config.h` for each required feature, and the manifest lists what was found.
- Adding LZO later needs this ADR superseded and the GPL source shipped with every image that has bsdtar.
- If OpenSSL 4 stops building with libarchive, dropping it loses nothing for zip and 7-Zip encryption, which CNG also provides.

## Alternatives considered

- Windows XmlLite instead of libxml2: drops libxml2 and libiconv, but whether Nano Server has `xmllite.dll` is unverified.
- Build without iconv: libarchive then skips libxml2, and with it XAR support through libxml2.
