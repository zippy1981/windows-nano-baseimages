# nanoserver-base-pwsh: nanoserver-base (bsdtar, jq, yq, Microsoft Edit) plus PowerShell 7 on Nano Server.
#
# Published as zippy1981/nanoserver-base:ltsc<version>-pwsh. PowerShell is in C:\Program Files\PowerShell\7,
# which is added to the machine PATH after C:\tools\bin.
#
# Licensing: PowerShell's licence (MIT) and third-party notices are in C:\Program Files\PowerShell\7 (LICENSE.txt
# and ThirdPartyNotices.txt), as shipped in the release zip. The base image's licences are in C:\tools\licenses.
#
# Build from this folder after building nanoserver-base (..\nanoserver-base\build.cmd does both):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 --build-arg BASE_IMAGE=nanoserver-base:ltsc2022 -t nanoserver-base:ltsc2022-pwsh .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The nanoserver-base image to add PowerShell to. CI passes the image it has just built and tested.
# Set with --build-arg BASE_IMAGE=nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}
# The Server Core image that downloads and verifies PowerShell. Only the unpacked PowerShell reaches the final image.
# Set with --build-arg DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2022-amd64.
ARG DOWNLOAD_IMAGE=mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64

FROM ${DOWNLOAD_IMAGE} AS download

SHELL ["powershell", "-NoLogo", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# PowerShell 7: https://github.com/PowerShell/PowerShell/releases
ENV POWERSHELL_VERSION=7.7.0 \
    POWERSHELL_SHA256=7c74e03b20a75b59715847439d046a6214b1863ee79b187872980f139bb4a05f

RUN $zip = 'C:\download\PowerShell.zip'; \
    New-Item -ItemType Directory -Path C:\download | Out-Null; \
    curl.exe -fsSL --retry 5 --retry-delay 5 -o $zip ('https://github.com/PowerShell/PowerShell/releases/download/v' + ${env:POWERSHELL_VERSION} + '/PowerShell-' + ${env:POWERSHELL_VERSION} + '-win-x64.zip'); \
    if ($LASTEXITCODE) { throw ('curl failed: ' + $LASTEXITCODE) }; \
    $hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash; \
    if ($hash -ne ${env:POWERSHELL_SHA256}.ToUpperInvariant()) { throw ('SHA-256 mismatch for PowerShell.zip: ' + $hash) }; \
    Expand-Archive -Path $zip -DestinationPath 'C:\pwsh'; \
    if (-not (Test-Path C:\pwsh\pwsh.exe) -or -not (Test-Path C:\pwsh\LICENSE.txt)) { throw 'PowerShell.zip did not contain pwsh.exe and LICENSE.txt' }

FROM ${BASE_IMAGE}

ARG WINDOWS_VERSION

ENV POWERSHELL_TELEMETRY_OPTOUT=1

COPY --from=download ["C:/pwsh", "C:/Program Files/PowerShell/7"]

# Append PowerShell to the machine PATH, after C:\tools\bin, read from the registry like the base image does. The value
# ends with a semicolon (C:\tools\bin;%SystemRoot%\system32;%SystemRoot%;), so none is added; the smoke test checks for ;;.
USER ContainerAdministrator
RUN for /f "skip=2 tokens=2,*" %a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do setx /M PATH "%bC:\Program Files\PowerShell\7"
USER ContainerUser

CMD ["pwsh"]
