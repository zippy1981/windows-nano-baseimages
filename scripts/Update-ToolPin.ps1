<#
.SYNOPSIS
Checks each pinned tool in the nanoserver-base Dockerfiles for a newer upstream release and opens one bump pull
request per tool.

.DESCRIPTION
Run by .github/workflows/watch-tool-versions.yml. For each tool it finds the latest release, takes the SHA-256 from
upstream's published checksums where there are any (jq's sha256sum.txt, yq's checksums, PowerShell's hashes.sha256), otherwise the
digest GitHub records for the release asset, and recomputes the hash of any licence file fetched from the same tag.
It then rewrites that tool's ENV block, commits to bump/<tool>-<version>, pushes, opens a pull request unless one
is already open, and dispatches the nanoserver-base and markdownlint workflows on the branch.

Pull requests and pushes made with GITHUB_TOKEN don't start pull_request or push workflows, so the checks are
started with workflow_dispatch, which does. Their check runs are on the branch's head commit, so they count for the
pull request.

.PARAMETER Tool
Only check these tools. Defaults to all: libarchive, jq, yq, edit, powershell.

.PARAMETER DryRun
Report what would change, and change nothing (no files, git, or GitHub writes).

.EXAMPLE
./scripts/Update-ToolPin.ps1 -DryRun
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
param(
    [ValidateSet('libarchive', 'jq', 'yq', 'edit', 'powershell')]
    [string[]] $Tool = @('libarchive', 'jq', 'yq', 'edit', 'powershell'),

    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repo = $env:GITHUB_REPOSITORY ? $env:GITHUB_REPOSITORY : 'zippy1981/windows-nano-baseimages'

function Get-LatestRelease([string] $Repository, [string] $TagPattern) {
    # The newest non-draft, non-prerelease release whose tag matches, by publication date
    $releases = gh api "repos/$Repository/releases?per_page=50" | ConvertFrom-Json
    if ($LASTEXITCODE) { throw "gh api failed for $Repository" }
    $releases | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match $TagPattern } |
        Sort-Object { [datetime]$_.published_at } -Descending | Select-Object -First 1
}

function Get-AssetDigest([object] $Release, [string] $Name) {
    $asset = $Release.assets | Where-Object name -EQ $Name
    if (-not $asset) { throw "$($Release.html_url) has no asset $Name" }
    if (-not $asset.PSObject.Properties['digest'] -or $asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "No SHA-256 digest for $Name" }
    $Matches[1]
}

function Get-UrlSha256([string] $Uri) {
    $file = New-TemporaryFile
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $file -MaximumRetryCount 3
        (Get-FileHash -Algorithm SHA256 $file).Hash.ToLowerInvariant()
    }
    finally { Remove-Item $file }
}

function Get-Tool([string] $Name) {
    switch ($Name) {
        'libarchive' {
            $r = Get-LatestRelease $repo '^static-\d+\.\d+\.\d+$'
            $v = $r.tag_name -replace '^static-', ''
            @{ Dockerfile = 'images/nanoserver-base/Dockerfile'; Version = $v; Pins = [ordered]@{
                    LIBARCHIVE_VERSION = $v
                    LIBARCHIVE_SHA256 = Get-AssetDigest $r "libarchive-$v-windows-x64-static-tools.zip"
                } }
        }
        'jq' {
            $r = Get-LatestRelease 'jqlang/jq' '^jq-\d+\.\d+(\.\d+)?$'
            $v = $r.tag_name -replace '^jq-', ''
            $sums = (Invoke-WebRequest -Uri "https://github.com/jqlang/jq/releases/download/$($r.tag_name)/sha256sum.txt").Content
            if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
            if ($sums -notmatch '(?m)^([0-9a-f]{64})\s+\*?jq-windows-amd64\.exe\s*$') { throw 'jq-windows-amd64.exe is not in sha256sum.txt' }
            $exe = $Matches[1]
            @{ Dockerfile = 'images/nanoserver-base/Dockerfile'; Version = $v; Pins = [ordered]@{
                    JQ_VERSION = $v
                    JQ_SHA256 = $exe
                    JQ_COPYING_SHA256 = Get-UrlSha256 "https://raw.githubusercontent.com/jqlang/jq/$($r.tag_name)/COPYING"
                } }
        }
        'yq' {
            $r = Get-LatestRelease 'mikefarah/yq' '^v\d+\.\d+\.\d+$'
            $v = $r.tag_name -replace '^v', ''
            # checksums has one line per asset: its name, then one hash per algorithm, in the order
            # checksums_hashes_order lists them
            $base = "https://github.com/mikefarah/yq/releases/download/$($r.tag_name)"
            $text = { param($Uri) $c = (Invoke-WebRequest -Uri $Uri).Content; ($c -is [byte[]]) ? [Text.Encoding]::UTF8.GetString($c) : $c }
            $order = @((& $text "$base/checksums_hashes_order") -split '\r?\n' | Where-Object { $_ })
            $column = [array]::IndexOf($order, 'SHA-256')
            if ($column -lt 0) { throw 'checksums_hashes_order has no SHA-256' }
            $line = (& $text "$base/checksums") -split '\r?\n' | Where-Object { $_ -match '^yq_windows_amd64\.exe\s' }
            if (-not $line) { throw 'yq_windows_amd64.exe is not in checksums' }
            $exe = (-split $line)[$column + 1]
            if ($exe -notmatch '^[0-9a-f]{64}$') { throw "checksums gives yq_windows_amd64.exe the SHA-256 '$exe'" }
            @{ Dockerfile = 'images/nanoserver-base/Dockerfile'; Version = $v; Pins = [ordered]@{
                    YQ_VERSION = $v
                    YQ_SHA256 = $exe
                    YQ_LICENSE_SHA256 = Get-UrlSha256 "https://raw.githubusercontent.com/mikefarah/yq/$($r.tag_name)/LICENSE"
                } }
        }
        'edit' {
            $r = Get-LatestRelease 'microsoft/edit' '^v\d+\.\d+\.\d+$'
            $v = $r.tag_name -replace '^v', ''
            @{ Dockerfile = 'images/nanoserver-base/Dockerfile'; Version = $v; Pins = [ordered]@{
                    EDIT_VERSION = $v
                    EDIT_SHA256 = Get-AssetDigest $r "edit-$v-x86_64-windows.zip"
                    EDIT_LICENSE_SHA256 = Get-UrlSha256 "https://raw.githubusercontent.com/microsoft/edit/$($r.tag_name)/LICENSE"
                } }
        }
        'powershell' {
            $r = Get-LatestRelease 'PowerShell/PowerShell' '^v\d+\.\d+\.\d+$'
            $v = $r.tag_name -replace '^v', ''
            # hashes.sha256 is UTF-16
            $file = New-TemporaryFile
            try {
                Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/$($r.tag_name)/hashes.sha256" -OutFile $file
                $sums = Get-Content -Raw -Path $file
            }
            finally { Remove-Item $file }
            if ($sums -notmatch "(?m)^([0-9a-fA-F]{64})\s+\*?PowerShell-$([regex]::Escape($v))-win-x64\.zip\s*$") { throw "PowerShell-$v-win-x64.zip is not in hashes.sha256" }
            @{ Dockerfile = 'images/nanoserver-base-pwsh/Dockerfile'; Version = $v; Pins = [ordered]@{
                    POWERSHELL_VERSION = $v
                    POWERSHELL_SHA256 = $Matches[1].ToLowerInvariant()
                } }
        }
    }
}

$opened = @()
foreach ($name in $Tool) {
    $t = Get-Tool $name
    $path = Join-Path $repoRoot $t.Dockerfile
    $text = [IO.File]::ReadAllText($path)
    $first = @($t.Pins.Keys)[0]
    if ($text -notmatch "(?m)\b$first=(\S+)") { throw "$first is not in $($t.Dockerfile)" }
    $current = $Matches[1]
    if ($current -eq $t.Version) { Write-Host "${name}: $current is current"; continue }
    if ([version]($t.Version -replace '[^\d.]', '') -lt [version]($current -replace '[^\d.]', '')) {
        Write-Host "${name}: pinned $current is newer than the latest release $($t.Version); leaving it"; continue
    }
    Write-Host "${name}: $current -> $($t.Version)"
    foreach ($pin in $t.Pins.GetEnumerator()) {
        if ($text -notmatch "(?m)\b$($pin.Key)=\S+") { throw "$($pin.Key) is not in $($t.Dockerfile)" }
        $text = $text -replace "(?m)\b$($pin.Key)=\S+", "$($pin.Key)=$($pin.Value)"
        Write-Host "  $($pin.Key)=$($pin.Value)"
    }
    if ($DryRun) { continue }

    $branch = "bump/$name-$($t.Version)"
    $existing = gh pr list --repo $repo --head $branch --state open --json number --jq '.[].number'
    if ($existing) { Write-Host "  pull request #$existing is already open"; continue }

    git -C $repoRoot switch -C $branch origin/main
    [IO.File]::WriteAllText($path, $text)
    git -C $repoRoot add $t.Dockerfile
    git -C $repoRoot commit -m "Bump $name to $($t.Version)" -m "Found by watch-tool-versions.yml. Hashes from upstream checksums or the release asset digest."
    git -C $repoRoot push --force-with-lease origin $branch
    if ($LASTEXITCODE) { throw "git push of $branch failed" }
    $body = @(
        "Bumps **$name** from ``$current`` to ``$($t.Version)`` in ``$($t.Dockerfile)``."
        ''
        '| Pin | Value |'
        '| --- | --- |'
        ($t.Pins.GetEnumerator() | ForEach-Object { "| ``$($_.Key)`` | ``$($_.Value)`` |" })
        ''
        'The nanoserver-base build and markdownlint were started on this branch with workflow_dispatch, because pull requests opened with GITHUB_TOKEN start no workflows.'
        ''
        'Opened by `.github/workflows/watch-tool-versions.yml`.'
    ) -join "`n"
    gh pr create --repo $repo --base main --head $branch --title "Bump $name to $($t.Version)" --body $body
    if ($LASTEXITCODE) { throw "gh pr create failed for $branch" }
    gh workflow run nanoserver-base.yml --repo $repo --ref $branch
    gh workflow run markdown-lint.yml --repo $repo --ref $branch
    $opened += $branch
    git -C $repoRoot switch --detach origin/main
}

if ($env:GITHUB_STEP_SUMMARY) {
    ($opened ? ($opened | ForEach-Object { "Opened $_" }) : 'Every tool is current, or already has a bump pull request.') | Add-Content $env:GITHUB_STEP_SUMMARY
}
