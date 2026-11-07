<#
.SYNOPSIS
Downloads a file and fails unless its SHA-256 matches the pinned hash.

.DESCRIPTION
Used by the download stage of the nanoserver-base Dockerfile, which runs Windows PowerShell 5.1 on Server Core.
It downloads with the curl.exe that Windows ships, because that only has to fetch the file; nothing it downloads
is unpacked with the Windows tar. A file whose hash doesn't match is deleted before the script throws, so a bad
download can't be used by a later step.

.PARAMETER Uri
The URL to download.

.PARAMETER Sha256
The expected SHA-256 of the file, in hex. Case doesn't matter.

.PARAMETER OutFile
Where to save the file.

.EXAMPLE
.\Save-VerifiedFile.ps1 -Uri https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-amd64.exe -Sha256 a6fc67fe... -OutFile C:\download\jq.exe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Uri,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string] $Sha256,

    [Parameter(Mandatory)]
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'

$parent = Split-Path -Path $OutFile -Parent
if ($parent -and -not (Test-Path -Path $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

& "$env:SystemRoot\System32\curl.exe" -fsSL --retry 5 --retry-delay 5 -o $OutFile $Uri
if ($LASTEXITCODE) {
    throw "Downloading $Uri failed with curl exit code $LASTEXITCODE"
}

$actual = (Get-FileHash -Algorithm SHA256 -Path $OutFile).Hash
if ($actual -ne $Sha256.ToUpperInvariant()) {
    Remove-Item -Path $OutFile -Force
    throw "SHA-256 mismatch for ${Uri}: expected $($Sha256.ToUpperInvariant()), got $actual"
}

Write-Verbose "Verified $OutFile ($actual)"
