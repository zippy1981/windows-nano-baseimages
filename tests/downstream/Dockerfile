# nanoserver-base-downstream-test: a throwaway image FROM nanoserver-base with PHP, MySQL and Helix, to prove that
# programs built with Visual C++ run on the base without copying the runtime DLLs in themselves (issue 14).
#
# It is built and run by tests/downstream/smoke-test.ps1 and never published. It adds nothing to System32: PHP, MySQL
# and Helix find vcruntime140.dll, vcruntime140_1.dll and msvcp140.dll only because nanoserver-base ships them.
#
# Licensing: the image is never distributed. Each program keeps the licence file from its own zip: PHP's
# license.txt in C:\php, MySQL's LICENSE (GPL-2.0) in C:\mysql and Helix's LICENSE (MPL-2.0) in C:\helix.
#
# Build from this folder, after building nanoserver-base (the smoke test does the same):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 --build-arg BASE_IMAGE=nanoserver-base:ltsc2022 -t nanoserver-base-downstream-test:ltsc2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The nanoserver-base image to test. CI passes the image it has just built.
# Set with --build-arg BASE_IMAGE=nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}
# The Server Core image that downloads and verifies the programs. Only the unpacked programs reach the final image.
# Set with --build-arg DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2022-amd64.
ARG DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64

# Named so the download stage can copy the base's bsdtar out of it
FROM ${BASE_IMAGE} AS base

FROM ${DOWNLOAD_IMAGE} AS download

SHELL ["powershell", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# PHP (non-thread-safe, VS17 build): https://windows.php.net/download/. SHA-256 from its sha256sum.txt.
ENV PHP_VERSION=8.5.12-1 \
    PHP_SHA256=2a36a2edcb7a5b9252f638fd5e4cf84d7f6e066092654220dc0b63e5cf4e9723
# MySQL 8.4 LTS: https://dev.mysql.com/downloads/mysql/8.4.html. MySQL publishes only an MD5
# (7b94489d5524dea9b27097068bea25a8, which matched), so this SHA-256 was computed here.
ENV MYSQL_VERSION=8.4.13 \
    MYSQL_SHA256=e9cd98b1d23f122987b1afca26ad942efec5891481103d48ae3cde237fa3ea54
# Helix: https://github.com/helix-editor/helix/releases
ENV HELIX_VERSION=25.07.1 \
    HELIX_SHA256=5c8325ced8bacd8418d62706f669e96d9c3578a9237526e34d546900cbc049b6

COPY --from=base C:/tools C:/tools

# Each zip is downloaded to a file, never through a pipe (issue 8), checked against its pin, and unpacked with the
# base's bsdtar. All three use plain Deflate.
RUN New-Item -ItemType Directory -Path C:\download, C:\out\php, C:\unpack | Out-Null; \
    $downloads = @( \
        @('php.zip', ${env:PHP_SHA256}, 'C:\out\php', ('https://windows.php.net/downloads/releases/archives/php-' + ${env:PHP_VERSION} + '-nts-Win32-vs17-x64.zip')), \
        @('mysql.zip', ${env:MYSQL_SHA256}, 'C:\unpack', ('https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-' + ${env:MYSQL_VERSION} + '-winx64.zip')), \
        @('helix.zip', ${env:HELIX_SHA256}, 'C:\unpack', ('https://github.com/helix-editor/helix/releases/download/' + ${env:HELIX_VERSION} + '/helix-' + ${env:HELIX_VERSION} + '-x86_64-windows.zip'))); \
    foreach ($d in $downloads) { \
        $zip = 'C:\download\' + $d[0]; \
        curl.exe -fsSL --retry 5 --retry-delay 5 -o $zip $d[3]; if ($LASTEXITCODE) { throw ('curl failed on ' + $d[3] + ': ' + $LASTEXITCODE) }; \
        $hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash; \
        if ($hash -ne $d[1].ToUpperInvariant()) { throw ('SHA-256 mismatch for ' + $d[0] + ': ' + $hash) }; \
        & C:\tools\bin\tar.exe -xf $zip -C $d[2]; if ($LASTEXITCODE) { throw ('tar failed on ' + $d[0] + ': ' + $LASTEXITCODE) } \
    }; \
    Move-Item ('C:\unpack\mysql-' + ${env:MYSQL_VERSION} + '-winx64') C:\out\mysql; \
    Move-Item ('C:\unpack\helix-' + ${env:HELIX_VERSION} + '-x86_64-windows') C:\out\helix; \
    Remove-Item -Recurse -Force C:\out\mysql\include, C:\out\mysql\docs, C:\out\mysql\lib\plugin\debug, C:\out\mysql\lib\mecab, C:\out\helix\contrib -ErrorAction SilentlyContinue; \
    Get-ChildItem -Recurse -File -Path C:\out -Include *.pdb, *.lib, *-debug.dll | Remove-Item -Force; \
    Set-Content -Path C:\out\php\php.ini -Encoding ascii -Value @('extension_dir=C:\php\ext', 'extension=curl', 'extension=intl', 'extension=mbstring', 'extension=openssl', 'extension=zip'); \
    foreach ($exe in 'php\php.exe', 'mysql\bin\mysqld.exe', 'mysql\bin\mysql.exe', 'helix\hx.exe') { \
        $stream = [IO.File]::OpenRead('C:\out\' + $exe); $mz = $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A; $stream.Dispose(); \
        if (-not $mz) { throw ($exe + ' is not a Windows executable') } \
    }; \
    if (Get-ChildItem -Recurse -Path C:\out -Include vcruntime*.dll, msvcp*.dll) { throw 'A zip ships its own Visual C++ runtime, so it would not test the base' }

FROM ${BASE_IMAGE}

COPY --from=download C:/out/php C:/php
COPY --from=download C:/out/mysql C:/mysql
COPY --from=download C:/out/helix C:/helix

ENV HELIX_RUNTIME="C:\\helix\\runtime"

CMD ["cmd"]
