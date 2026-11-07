# nanoserver-base: Nano Server with a modern tar (libarchive bsdtar 3.8), jq and Microsoft Edit on PATH.
#
# The tools are in C:\tools\bin, which comes first on the machine PATH, so tar finds this repo's bsdtar instead of
# the old C:\Windows\System32\tar.exe (docs/adr/0002). The System32 files are left as they are. curl is Windows'
# own C:\Windows\System32\curl.exe: it uses Schannel and the Windows certificate store, which curl.se's LibreSSL
# build can't do on Nano Server (issue 5).
#
# Licensing: each tool's licence files are in C:\tools\licenses\<tool>. libarchive's static tools link the
# LGPL-2.1 libiconv. Its release tarball, as published with this repo's static-tools release, is in
# C:\tools\licenses\libarchive\sources. Everything else shipped is under a permissive licence (BSD, MIT).
#
# Build from this folder (build.cmd does the same):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t nanoserver-base:ltsc2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to Nano Server for WINDOWS_VERSION; CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64
# The Server Core image that downloads, verifies and unpacks the tools. Nothing from it but C:\tools reaches the
# final image. Set with --build-arg DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2022-amd64.
ARG DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64

FROM ${DOWNLOAD_IMAGE} AS download

SHELL ["powershell", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# libarchive static tools (bsdtar and friends), built by this repo: https://github.com/zippy1981/windows-nano-baseimages/releases
ENV LIBARCHIVE_VERSION=3.8.11 \
    LIBARCHIVE_SHA256=959fb0b232feab4b00972fa1e80c1195abc64288fc1c675371d3e8073bcfbb10
# jq: https://github.com/jqlang/jq/releases. The release has no licence file, so COPYING comes from the same tag.
ENV JQ_VERSION=1.8.2 \
    JQ_SHA256=a6fc67fedaf9128a3309a1e2ebb8b986aeccf70122ee46d2cb4849e423f0c627 \
    JQ_COPYING_SHA256=ad2b4a266b2268939c1446979759706077421cf906a203aa188c6f396e8cfd74
# Microsoft Edit: https://github.com/microsoft/edit/releases. The zip has no licence file, so LICENSE comes from the same tag.
ENV EDIT_VERSION=2.0.0 \
    EDIT_SHA256=97b8f2c667faea8f211af5f9c879602949164911d74d16f540bbe31ad46c14cb \
    EDIT_LICENSE_SHA256=d25deed12d803f6c973597348627b1939e2d19bbc28fda83c93ea0cde44702da

COPY Save-VerifiedFile.ps1 C:/build/

RUN C:\build\Save-VerifiedFile.ps1 -OutFile C:\download\libarchive.zip -Sha256 ${env:LIBARCHIVE_SHA256} \
        -Uri ('https://github.com/zippy1981/windows-nano-baseimages/releases/download/static-' + ${env:LIBARCHIVE_VERSION} + '/libarchive-' + ${env:LIBARCHIVE_VERSION} + '-windows-x64-static-tools.zip'); \
    C:\build\Save-VerifiedFile.ps1 -OutFile C:\download\jq.exe -Sha256 ${env:JQ_SHA256} \
        -Uri ('https://github.com/jqlang/jq/releases/download/jq-' + ${env:JQ_VERSION} + '/jq-windows-amd64.exe'); \
    C:\build\Save-VerifiedFile.ps1 -OutFile C:\download\jq-COPYING -Sha256 ${env:JQ_COPYING_SHA256} \
        -Uri ('https://raw.githubusercontent.com/jqlang/jq/jq-' + ${env:JQ_VERSION} + '/COPYING'); \
    C:\build\Save-VerifiedFile.ps1 -OutFile C:\download\edit.zip -Sha256 ${env:EDIT_SHA256} \
        -Uri ('https://github.com/microsoft/edit/releases/download/v' + ${env:EDIT_VERSION} + '/edit-' + ${env:EDIT_VERSION} + '-x86_64-windows.zip'); \
    C:\build\Save-VerifiedFile.ps1 -OutFile C:\download\edit-LICENSE -Sha256 ${env:EDIT_LICENSE_SHA256} \
        -Uri ('https://raw.githubusercontent.com/microsoft/edit/v' + ${env:EDIT_VERSION} + '/LICENSE')

# Our own release zip uses plain Deflate, so Expand-Archive can unpack it. Edit's zip is unpacked with the bsdtar it
# contains, never with Windows' tar (see the windows-nano-demos failures in issue 5). edit.pdb is left out.
RUN Expand-Archive -Path C:\download\libarchive.zip -DestinationPath C:\unpack; \
    $la = 'C:\unpack\libarchive-' + ${env:LIBARCHIVE_VERSION} + '-windows-x64-static-tools'; \
    $bin = New-Item -ItemType Directory -Path C:\tools\bin; \
    $lic = 'C:\tools\licenses'; \
    Copy-Item -Path ($la + '\bsdtar.exe') -Destination ($bin.FullName + '\tar.exe'); \
    Copy-Item -Path ($la + '\bsdcpio.exe'), ($la + '\bsdcat.exe'), ($la + '\bsdunzip.exe') -Destination $bin; \
    New-Item -ItemType Directory -Path ($lic + '\libarchive') | Out-Null; \
    Copy-Item -Recurse -Path ($la + '\licenses\*'), ($la + '\sources'), ($la + '\MANIFEST.txt'), ($la + '\manifest.json') -Destination ($lic + '\libarchive'); \
    Copy-Item -Path C:\download\jq.exe -Destination $bin; \
    New-Item -ItemType Directory -Path ($lic + '\jq') | Out-Null; \
    Copy-Item -Path C:\download\jq-COPYING -Destination ($lic + '\jq\COPYING'); \
    & ($bin.FullName + '\tar.exe') -xf C:\download\edit.zip -C C:\unpack; if ($LASTEXITCODE) { throw ('tar failed on edit.zip: ' + $LASTEXITCODE) }; \
    Copy-Item -Path ('C:\unpack\edit-' + ${env:EDIT_VERSION} + '-x86_64-windows\edit.exe') -Destination $bin; \
    New-Item -ItemType Directory -Path ($lic + '\edit') | Out-Null; \
    Copy-Item -Path C:\download\edit-LICENSE -Destination ($lic + '\edit\LICENSE'); \
    Get-ChildItem -Path $bin -Filter *.exe | ForEach-Object { \
        $stream = [IO.File]::OpenRead($_.FullName); $mz = $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A; $stream.Dispose(); \
        if (-not $mz -or $_.Length -lt 1024) { throw ($_.Name + ' is not a Windows executable') } \
    }; \
    Get-ChildItem -Recurse -File C:\tools | Format-Table -AutoSize Length, FullName

FROM ${BASE_IMAGE}

COPY --from=download C:/tools C:/tools

# Put C:\tools\bin first on the machine PATH (docs/adr/0002). The value comes from the registry, not %PATH%, so no
# user PATH is folded into it, and %SystemRoot% stays unexpanded. Downstream images can still use setx PATH for their
# own (user) entries, which Windows appends after the machine PATH.
USER ContainerAdministrator
RUN for /f "skip=2 tokens=2,*" %a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do setx /M PATH "C:\tools\bin;%b"
USER ContainerUser

LABEL org.opencontainers.image.source="https://github.com/zippy1981/windows-nano-baseimages" \
      org.opencontainers.image.licenses="BSD-2-Clause AND MIT AND LGPL-2.1-or-later"

CMD ["cmd"]
