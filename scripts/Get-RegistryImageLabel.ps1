<#
.SYNOPSIS
Reads the labels of a published Windows image on Docker Hub without pulling it.

.DESCRIPTION
Gets an anonymous pull token, reads the tag's manifest (choosing the windows/amd64 entry of a manifest list), then
the image config, and returns its labels as a hashtable. Returns nothing if the tag doesn't exist yet.

.PARAMETER Repository
The Docker Hub repository, for example zippy1981/nanoserver-base.

.PARAMETER Tag
The tag, for example ltsc2025.

.EXAMPLE
./scripts/Get-RegistryImageLabel.ps1 -Repository zippy1981/nanoserver-base -Tag ltsc2025
#>
[CmdletBinding()]
[OutputType([hashtable])]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(?:[._-][a-z0-9]+)*/[a-z0-9]+(?:[._-][a-z0-9]+)*$')]
    [string] $Repository,

    [Parameter(Mandatory)]
    [ValidatePattern('^[\w][\w.-]{0,127}$')]
    [string] $Tag
)

$ErrorActionPreference = 'Stop'

$token = (Invoke-RestMethod -Uri "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${Repository}:pull").token
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
}
$base = "https://registry-1.docker.io/v2/$Repository"

$response = Invoke-WebRequest -Uri "$base/manifests/$Tag" -Headers $headers -SkipHttpErrorCheck
if ($response.StatusCode -eq 404) { return }
if ($response.StatusCode -ne 200) { throw "Reading ${Repository}:$Tag failed with HTTP $($response.StatusCode)" }
$manifest = $response.Content | ConvertFrom-Json

if ($manifest.PSObject.Properties['manifests']) {
    $entry = $manifest.manifests | Where-Object { $_.platform.os -eq 'windows' -and $_.platform.architecture -eq 'amd64' } | Select-Object -First 1
    if (-not $entry) { throw "${Repository}:$Tag has no windows/amd64 image" }
    $manifest = Invoke-RestMethod -Uri "$base/manifests/$($entry.digest)" -Headers $headers
}

$config = Invoke-RestMethod -Uri "$base/blobs/$($manifest.config.digest)" -Headers @{ Authorization = "Bearer $token" }
$labels = @{}
if ($config.config.PSObject.Properties['Labels'] -and $config.config.Labels) {
    foreach ($p in $config.config.Labels.PSObject.Properties) { $labels[$p.Name] = $p.Value }
}
$labels
