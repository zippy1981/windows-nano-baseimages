# mxe-libarchive: a Linux MXE cross-compile environment that builds libarchive for 64-bit Windows.
# It holds MXE's x86_64-w64-mingw32.static and x86_64-w64-mingw32.shared targets with libarchive's
# dependencies, and runs as the non-root user "mxe". CI rebuilds it weekly, and when mxe/ changes on
# main, and pushes it to GHCR (.github/workflows/mxe-image.yml). Building it takes about an hour on a
# hosted runner.
#
#   docker build --build-arg MXE_JOBS=8 -t mxe-libarchive:local mxe
#
# Licences: MXE builds every dependency from source. record-mxe-info.sh copies each linked package's
# licence files to /opt/mxe/licenses/<package>/, and the LGPL libiconv release tarball to /opt/mxe/sources/,
# so scripts/build-libarchive.sh can ship them in every package it makes.

# The Ubuntu LTS base, pinned by digest (ubuntu:24.04, resolved on 2026-11-06).
#   --build-arg UBUNTU_IMAGE=ubuntu:24.04@sha256:<digest>
ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

FROM ${UBUNTU_IMAGE}

# The MXE commit to build (https://github.com/mxe/mxe). A change here rebuilds the whole toolchain.
#   --build-arg MXE_COMMIT=a6738d9d9f0723c04a26324655f42c8063359837
ARG MXE_COMMIT=a6738d9d9f0723c04a26324655f42c8063359837

# The MXE packages to build for both targets. cc is MXE's GCC toolchain; the rest are libarchive's
# dependencies (see docs/adr/0004-libarchive-feature-set.md for why lzo, nettle and pcre are left out).
#   --build-arg MXE_PACKAGES="cc zlib bzip2 xz lz4 zstd openssl expat libxml2 libiconv pcre2"
ARG MXE_PACKAGES="cc zlib bzip2 xz lz4 zstd openssl expat libxml2 libiconv pcre2"

# The yq release scripts/build-libarchive.sh reads its configuration with (mikefarah/yq v4,
# https://github.com/mikefarah/yq/releases), and the SHA-256 of its yq_linux_amd64 from that release's
# checksums file (the SHA-256 column, named in checksums_hashes_order).
#   --build-arg YQ_VERSION=4.54.1 --build-arg YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
ARG YQ_VERSION=4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f

# Parallel make jobs inside each MXE package build (MXE's JOBS). Defaults to the number of CPUs.
#   --build-arg MXE_JOBS=4
ARG MXE_JOBS=

# MXE's documented Debian and Ubuntu requirements (https://mxe.cc/#requirements-debian), plus what
# scripts/build-libarchive.sh needs: cmake, file, gpgv, jq, zip and curl (and yq, below).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      autoconf automake autopoint bash bison bzip2 ca-certificates clang cmake curl file flex g++ \
      g++-multilib gettext git gperf gpgv gnupg intltool jq libc6-dev-i386 libclang-dev \
      libgdk-pixbuf-2.0-dev libgl-dev libltdl-dev libpcre2-dev libssl-dev libtool-bin \
      libxml-parser-perl llvm-dev lzip make openssl p7zip-full patch perl pkg-config python3 \
      python3-mako python3-packaging python3-pkg-resources python3-setuptools python3-yaml \
      python-is-python3 ruby sed sqlite3 unzip wget xz-utils zip \
 && rm -rf /var/lib/apt/lists/*

# yq for scripts/build-libarchive.sh, pinned by version and SHA-256. It is MIT-licensed, and only builds;
# nothing from it ships in the libarchive packages.
RUN curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --retry 5 \
      --output /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
 && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum --check --strict \
 && chmod 0755 /usr/local/bin/yq \
 && yq --version

# uid 1001 matches the "runner" user on GitHub-hosted Ubuntu runners, so a bind-mounted workspace is writable.
RUN groupadd --gid 1001 mxe \
 && useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash mxe \
 && install -d -o mxe -g mxe /opt/mxe

USER mxe
WORKDIR /opt/mxe

COPY --chown=mxe:mxe record-mxe-info.sh /opt/mxe-tools/record-mxe-info.sh

# Fetch the pinned commit only, build both targets in one tree, record versions and licences, then drop
# the downloads, logs and temporary trees so the layer holds only the installed toolchain. ccache is
# off (MXE_USE_CCACHE empty): a one-shot build gains nothing from it, and with it on MXE's CMake
# toolchain points at wrappers in the .ccache tree.
RUN git init -q . \
 && git remote add origin https://github.com/mxe/mxe.git \
 && git fetch -q --depth 1 origin "${MXE_COMMIT}" \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${MXE_COMMIT}" \
 && make --jobs=2 \
      MXE_TARGETS='x86_64-w64-mingw32.static x86_64-w64-mingw32.shared' \
      JOBS="${MXE_JOBS:-$(nproc)}" \
      MXE_USE_CCACHE= \
      ${MXE_PACKAGES} \
 && bash /opt/mxe-tools/record-mxe-info.sh /opt/mxe "${MXE_PACKAGES}" \
 && rm -rf pkg log tmp-* .ccache \
 && chmod -R a+rX /opt/mxe

ENV PATH=/opt/mxe/usr/bin:${PATH} \
    MXE_DIR=/opt/mxe

LABEL org.opencontainers.image.title="mxe-libarchive" \
      org.opencontainers.image.description="MXE x86_64-w64-mingw32 static and shared targets with libarchive's dependencies" \
      org.opencontainers.image.source="https://github.com/zippy1981/windows-nano-baseimages" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /work
CMD ["/bin/bash"]
