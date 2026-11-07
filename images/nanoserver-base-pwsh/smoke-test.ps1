<#
.SYNOPSIS
Smoke-tests a nanoserver-base-pwsh image: PowerShell 7 runs as ContainerUser and reports the pinned version, and
the base image's tools still come first.

.DESCRIPTION
Runs on the CI runner with PowerShell 7. The base image's own checks, including every archive, are run by
images/nanoserver-base/smoke-test.ps1 against the base image. This script only checks what the pwsh layer adds or
could break. The test fails, with a list of every problem, if any check fails.

.PARAMETER Image
The image to test, for example nanoserver-base:ci-2025-pwsh-<sha>.

.EXAMPLE
./images/nanoserver-base-pwsh/smoke-test.ps1 -Image nanoserver-base:ltsc2025-pwsh
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
param(
    [Parameter(Mandatory)]
    [string] $Image
)

$ErrorActionPreference = 'Stop'

$dockerfile = Get-Content -Raw (Join-Path $PSScriptRoot 'Dockerfile')
if ($dockerfile -notmatch '(?m)\bPOWERSHELL_VERSION=(\S+)') { throw 'POWERSHELL_VERSION is not set in the Dockerfile' }
$version = $Matches[1]

# One pwsh run that reports everything as JSON. Single quotes only: docker passes the argument to pwsh as is.
$script = @'
$tar = (Get-Command tar.exe).Source
$curl = (Get-Command curl.exe).Source
[ordered]@{
    version = $PSVersionTable.PSVersion.ToString()
    user = [Environment]::UserName
    tar = $tar
    tarVersion = (& tar --version | Select-Object -First 1)
    curl = $curl
    jq = ('{"a":[1,2]}' | jq -c .a)
    https = (Invoke-WebRequest -UseBasicParsing -Uri https://github.com/jqlang/jq/releases/download/jq-1.8.2/sha256sum.txt).StatusCode
    # pwsh puts its own $PSHOME first on its process PATH, so the machine PATH is read from the registry
    machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
} | ConvertTo-Json -Compress
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
$output = docker run --rm --user ContainerUser $Image pwsh -NoLogo -NoProfile -EncodedCommand $encoded
$exit = $LASTEXITCODE

$failures = [Collections.Generic.List[string]]::new()
if ($exit) { $failures.Add("pwsh exited with $exit. Output: $output") }
else {
    $r = ($output | Select-Object -Last 1) | ConvertFrom-Json
    if ($r.version -ne $version) { $failures.Add("pwsh reports $($r.version), expected $version") }
    if ($r.user -ne 'ContainerUser') { $failures.Add("ran as $($r.user), expected ContainerUser") }
    if ($r.tar -ne 'C:\tools\bin\tar.exe') { $failures.Add("tar.exe resolves to $($r.tar), expected C:\tools\bin\tar.exe") }
    if ($r.tarVersion -notmatch '^bsdtar ') { $failures.Add("tar --version printed $($r.tarVersion)") }
    if ($r.curl -ne 'C:\Windows\system32\curl.exe') { $failures.Add("curl.exe resolves to $($r.curl), expected C:\Windows\system32\curl.exe") }
    if ($r.jq -ne '[1,2]') { $failures.Add("jq printed $($r.jq), expected [1,2]") }
    if ($r.https -ne 200) { $failures.Add("Invoke-WebRequest over HTTPS returned $($r.https)") }
    if ($r.machinePath -notmatch '(?i)\AC:\\tools\\bin;.*;C:\\Program Files\\PowerShell\\7\z' -or $r.machinePath -match ';;') { $failures.Add("machine PATH is $($r.machinePath)") }
    $report = @("### Smoke test: $Image", '', '```json', ($r | ConvertTo-Json), '```')
    $report | ForEach-Object { Write-Host $_ }
    if ($env:GITHUB_STEP_SUMMARY) { $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "::error::$_" }
    throw "$($failures.Count) smoke test failures in $Image"
}
Write-Host "All smoke tests passed for $Image"
