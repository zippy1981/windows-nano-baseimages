<#
.SYNOPSIS
Labels the tested nanoserver-base images and pushes them to Docker Hub with the tags from ADR 0004.

.DESCRIPTION
Adds the OCI labels in a one-line build on top of each tested image, so the pushed layers are exactly the tested
ones, then pushes these tags:

  <repo>:ltsc<ver>                          <repo>:ltsc<ver>-pwsh
  <repo>:ltsc<ver>-<os-build>-<sha7>        <repo>:ltsc<ver>-pwsh-<os-build>-<sha7>

The login uses DOCKERHUB_USERNAME and DOCKERHUB_TOKEN from the environment, in a throwaway Docker config folder,
because runner containers persist between jobs. Every tag is attempted; failures are listed and fail the script at
the end.

.PARAMETER Image
The tested base image.

.PARAMETER PwshImage
The tested -pwsh image.

.PARAMETER Repository
The Docker Hub repository, for example zippy1981/nanoserver-base.

.PARAMETER WindowsVersion
2019, 2022 or 2025.

.PARAMETER BaseImage
The Nano Server image the build used, as name@digest. Recorded in the base.name and base.digest labels.

.PARAMETER Revision
The git commit the images were built from.

.PARAMETER RepositoryUrl
The GitHub repository URL, for the source and documentation labels.

.EXAMPLE
./scripts/Publish-Image.ps1 -Image nanoserver-base:ci-2025-abc -PwshImage nanoserver-base:ci-2025-pwsh-abc -Repository zippy1981/nanoserver-base -WindowsVersion 2025 -BaseImage mcr.microsoft.com/windows/nanoserver@sha256:... -Revision abc... -RepositoryUrl https://github.com/zippy1981/windows-nano-baseimages
#>
[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
param(
    [Parameter(Mandatory)] [string] $Image,
    [Parameter(Mandatory)] [string] $PwshImage,
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [ValidateSet('2019', '2022', '2025')] [string] $WindowsVersion,
    [Parameter(Mandatory)] [ValidatePattern('^[^@\s]+@sha256:[0-9a-f]{64}$')] [string] $BaseImage,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $Revision,
    [Parameter(Mandatory)] [string] $RepositoryUrl
)

$ErrorActionPreference = 'Stop'

if (-not $env:DOCKERHUB_USERNAME -or -not $env:DOCKERHUB_TOKEN) {
    throw 'DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must be set in the "Docker Hub zippy1981" environment'
}

function Invoke-WithRetry([string] $What, [scriptblock] $Action, [int] $Attempts = 3) {
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        # Out-Host: the command's output must not become part of this function's return value
        & $Action | Out-Host
        if (-not $LASTEXITCODE) { return $true }
        Write-Host "::warning::$What failed (attempt $attempt of $Attempts, exit $LASTEXITCODE)"
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds (15 * $attempt) }
    }
    $false
}

$baseName, $baseDigest = $BaseImage -split '@', 2
$created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$sha7 = $Revision.Substring(0, 7)
$plan = @(
    @{ Source = $Image; Dockerfile = 'images/nanoserver-base/Dockerfile'; Suffix = '' }
    @{ Source = $PwshImage; Dockerfile = 'images/nanoserver-base-pwsh/Dockerfile'; Suffix = '-pwsh' }
)

$env:DOCKER_CONFIG = Join-Path ([IO.Path]::GetTempPath()) "docker-config-$([guid]::NewGuid().ToString('n'))"
New-Item -ItemType Directory -Path $env:DOCKER_CONFIG | Out-Null
$failed = @()
$pushed = @()
$cleanup = @()
try {
    if (-not (Invoke-WithRetry 'docker login' { $env:DOCKERHUB_TOKEN | docker login --username $env:DOCKERHUB_USERNAME --password-stdin })) {
        throw 'docker login failed after 3 attempts'
    }
    foreach ($p in $plan) {
        $labels = [ordered]@{
            'org.opencontainers.image.revision' = $Revision
            'org.opencontainers.image.source' = $RepositoryUrl
            'org.opencontainers.image.created' = $created
            'org.opencontainers.image.title' = "nanoserver-base$($p.Suffix)"
            # The Dockerfile header's first line is the image description (dockerfile-docs skill)
            'org.opencontainers.image.description' = (Get-Content -Path $p.Dockerfile -TotalCount 1) -replace '^# [\w.-]+: ', ''
            'org.opencontainers.image.documentation' = "$RepositoryUrl/blob/$Revision/README.md"
            'org.opencontainers.image.url' = "https://hub.docker.com/r/$Repository"
            'org.opencontainers.image.base.name' = $baseName
            'org.opencontainers.image.base.digest' = $baseDigest
        }
        $labelArgs = foreach ($label in $labels.GetEnumerator()) { '--label'; "$($label.Key)=$($label.Value)" }
        $labelled = "$($p.Source)-labelled"
        $cleanup += $labelled
        "FROM $($p.Source)" | docker build --memory 4g @labelArgs -t $labelled -
        if ($LASTEXITCODE) { throw "labelling $($p.Source) failed: $LASTEXITCODE" }
        $osBuild = docker image inspect $labelled --format '{{.OsVersion}}'
        foreach ($tag in "ltsc$WindowsVersion$($p.Suffix)", "ltsc$WindowsVersion$($p.Suffix)-$osBuild-$sha7") {
            $ref = "${Repository}:$tag"
            $cleanup += $ref
            docker tag $labelled $ref
            if (-not $PSCmdlet.ShouldProcess($ref, 'docker push')) { continue }
            if (Invoke-WithRetry "docker push $ref" { docker push $ref }) { $pushed += $ref } else { $failed += $ref }
        }
    }
}
finally {
    docker logout | Out-Null
    Remove-Item -Recurse -Force $env:DOCKER_CONFIG
    foreach ($ref in $cleanup) { docker rmi --no-prune $ref 2>$null | Out-Null }
}

$report = @($pushed | ForEach-Object { "Pushed $_" }) + @($failed | ForEach-Object { "**Failed** to push $_" })
$report | Out-Host
if ($env:GITHUB_STEP_SUMMARY) { $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }
if ($failed) { throw "push failed for $($failed.Count) tags: $($failed -join ', ')" }
