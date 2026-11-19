<#
.SYNOPSIS
Reads the labels of a published Windows image on Docker Hub without pulling it.

.DESCRIPTION
Gets an anonymous pull token, reads the tag's manifest (choosing the windows/amd64 entry of a manifest list), then
the image config, and returns its labels as a hashtable. Returns nothing if the tag doesn't exist yet.

Every registry request goes through Invoke-RegistryJson, which decodes the body itself: Docker Hub serves manifests
as application/vnd.docker.distribution.manifest.v2+json and similar types, which PowerShell doesn't treat as text or
JSON, so Invoke-WebRequest returns them as bytes and Invoke-RestMethod as an unparsed string. Any failure names the
URL, the HTTP status and the registry's reply.

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

function Invoke-RegistryJson {
    <#
    .SYNOPSIS
    GETs a registry URL and returns the parsed JSON body, or $null for a 404 when -AllowNotFound is set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Headers = @{},
        [switch] $AllowNotFound
    )
    try {
        $response = Invoke-WebRequest -Uri $Uri -Headers $Headers -SkipHttpErrorCheck
    }
    catch {
        throw "GET $Uri failed: $($_.Exception.Message)"
    }
    # Content is a byte[] for content types PowerShell doesn't know as text, which includes the registry's own types
    $body = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { [string] $response.Content }
    $status = [int] $response.StatusCode
    if ($status -eq 404 -and $AllowNotFound) { return $null }
    if ($status -ne 200) {
        $excerpt = ($body -replace '\s+', ' ').Trim()
        if ($excerpt.Length -gt 300) { $excerpt = $excerpt.Substring(0, 300) + '...' }
        throw "GET $Uri returned HTTP ${status}: $excerpt"
    }
    try {
        $body | ConvertFrom-Json
    }
    catch {
        throw "GET $Uri returned HTTP 200 with a body that isn't JSON ($($response.Headers['Content-Type'])): $($_.Exception.Message)"
    }
}

function Assert-Digest {
    [CmdletBinding()]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Digest,
        [Parameter(Mandatory)] [string] $Source
    )
    if ($Digest -notmatch '^sha256:[0-9a-f]{64}$') {
        throw "$Source has no valid digest (got '$Digest'), so there is no blob to read"
    }
}

$tokenUri = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${Repository}:pull"
$token = (Invoke-RegistryJson -Uri $tokenUri).token
if (-not $token) { throw "GET $tokenUri returned no token" }

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
}
$base = "https://registry-1.docker.io/v2/$Repository"

$manifestUri = "$base/manifests/$Tag"
$manifest = Invoke-RegistryJson -Uri $manifestUri -Headers $headers -AllowNotFound
if ($null -eq $manifest) { return }

if ($manifest.PSObject.Properties['manifests']) {
    $entry = $manifest.manifests | Where-Object { $_.platform.os -eq 'windows' -and $_.platform.architecture -eq 'amd64' } | Select-Object -First 1
    if (-not $entry) { throw "${Repository}:$Tag ($manifestUri) has no windows/amd64 image" }
    Assert-Digest -Digest $entry.digest -Source "The windows/amd64 entry of $manifestUri"
    $manifestUri = "$base/manifests/$($entry.digest)"
    $manifest = Invoke-RegistryJson -Uri $manifestUri -Headers $headers
}

$configDigest = if ($manifest.PSObject.Properties['config']) { $manifest.config.digest } else { $null }
Assert-Digest -Digest $configDigest -Source "The config of $manifestUri (mediaType '$($manifest.mediaType)')"

# The blob request redirects to Docker's CDN; PowerShell drops the Authorization header when the host changes
$config = Invoke-RegistryJson -Uri "$base/blobs/$configDigest" -Headers @{ Authorization = "Bearer $token" }
$labels = @{}
if ($config.config.PSObject.Properties['Labels'] -and $config.config.Labels) {
    foreach ($p in $config.config.Labels.PSObject.Properties) { $labels[$p.Name] = $p.Value }
}
$labels
