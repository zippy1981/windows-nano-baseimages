<#
.SYNOPSIS
Helpers for the tar extraction tests: a verified download cache, the expected contents of each archive, and a
comparison against what tar extracted in the container.

.DESCRIPTION
Runs on the CI runner (PowerShell 7), not in the image. The expected contents never come from the tar under test:
zips are read through .NET's System.IO.Compression, which reads the central directory and supports Deflate64; the 7z
uses the path and size list in tests/expected, which was read from its headers with py7zr.
#>

Set-StrictMode -Version Latest

function Save-TestArchive {
    <#
    .SYNOPSIS
    Makes sure every archive in tests/archives.json is in the cache directory, with the pinned SHA-256.

    .DESCRIPTION
    The cache directory lives on the runner (by default under RUNNER_TOOL_CACHE), so each runner downloads an archive
    once. A cached file whose hash doesn't match is downloaded again.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
    param(
        [Parameter(Mandatory)] [object[]] $Archive,
        [Parameter(Mandatory)] [string] $CacheDirectory
    )

    New-Item -ItemType Directory -Force -Path $CacheDirectory | Out-Null
    foreach ($entry in $Archive) {
        $path = Join-Path $CacheDirectory (Get-ArchiveFileName $entry)
        if ((Test-Path $path) -and (Get-FileHash -Algorithm SHA256 $path).Hash -eq $entry.sha256.ToUpperInvariant()) {
            Write-Verbose "Cached: $path"
            continue
        }
        Write-Host "Downloading $($entry.url)"
        $partial = "$path.partial"
        Invoke-WebRequest -Uri $entry.url -OutFile $partial -MaximumRetryCount 5 -RetryIntervalSec 10
        $hash = (Get-FileHash -Algorithm SHA256 $partial).Hash
        if ($hash -ne $entry.sha256.ToUpperInvariant()) {
            Remove-Item $partial
            throw "SHA-256 mismatch for $($entry.url): expected $($entry.sha256), got $hash"
        }
        Move-Item -Force $partial $path
    }
}

function Get-ArchiveFileName {
    <#
    .SYNOPSIS
    The file name an archive is cached and copied as: the last segment of its URL.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [object] $Entry)
    ([uri]$Entry.url).Segments[-1]
}

function Get-ExpectedFile {
    <#
    .SYNOPSIS
    The files an archive should extract to, as a hashtable of relative path to @{ Size; Sha256 }.

    .DESCRIPTION
    For a zip, read from its central directory and hashed by decompressing each entry with .NET. The result is
    cached next to the archive as <file>.expected.json. For anything else, read from tests/expected/<file>.json,
    which has sizes but no hashes (Sha256 is $null).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [object] $Entry,
        [Parameter(Mandatory)] [string] $CacheDirectory,
        [Parameter(Mandatory)] [string] $ExpectedDirectory
    )

    $file = Get-ArchiveFileName $Entry
    $expected = @{}
    if ($file -notlike '*.zip') {
        $listing = Get-Content -Raw (Join-Path $ExpectedDirectory "$file.json") | ConvertFrom-Json
        foreach ($f in $listing.files) { $expected[$f.path] = @{ Size = [long]$f.size; Sha256 = $null } }
        return $expected
    }

    $cached = Join-Path $CacheDirectory "$file.$($Entry.sha256).expected.json"
    if (Test-Path $cached) {
        foreach ($p in (Get-Content -Raw $cached | ConvertFrom-Json -AsHashtable).GetEnumerator()) {
            $expected[$p.Key] = @{ Size = [long]$p.Value.Size; Sha256 = $p.Value.Sha256 }
        }
        return $expected
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $CacheDirectory $file))
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        foreach ($zipEntry in $zip.Entries) {
            $name = $zipEntry.FullName -replace '\\', '/'
            if ($name.EndsWith('/')) { continue }
            $stream = $zipEntry.Open()
            try { $hash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() } finally { $stream.Dispose() }
            $expected[$name] = @{ Size = $zipEntry.Length; Sha256 = $hash }
        }
    }
    finally { $zip.Dispose() }
    $expected | ConvertTo-Json -Depth 3 -Compress | Set-Content -Path $cached
    $expected
}

function ConvertFrom-Mtree {
    <#
    .SYNOPSIS
    Parses bsdtar's mtree output (--options !all,type,size,sha256) into a hashtable of path to @{ Size; Sha256 }.
    Only regular files are returned. mtree escapes unusual characters in names as \ooo octal, which is decoded.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Line)

    $files = @{}
    foreach ($l in $Line) {
        if (-not $l -or $l.StartsWith('#')) { continue }
        $parts = $l -split ' '
        $keywords = @{}
        foreach ($kv in $parts[1..($parts.Count - 1)]) { $k, $v = $kv -split '=', 2; $keywords[$k] = $v }
        if ($keywords['type'] -ne 'file') { continue }
        $bytes = [Collections.Generic.List[byte]]::new()
        $raw = $parts[0]
        for ($i = 0; $i -lt $raw.Length; $i++) {
            if ($raw[$i] -eq '\' -and $i + 3 -lt $raw.Length -and $raw.Substring($i + 1, 3) -match '^[0-7]{3}$') {
                $bytes.Add([Convert]::ToByte($raw.Substring($i + 1, 3), 8)); $i += 3
            }
            else { $bytes.AddRange([Text.Encoding]::UTF8.GetBytes([string]$raw[$i])) }
        }
        # bsdtar writes names in the container's ANSI code page (1252 on Nano Server en-US), not UTF-8, so a name
        # that isn't valid UTF-8 is read as Windows-1252
        try { $name = [Text.UTF8Encoding]::new($false, $true).GetString($bytes.ToArray()) }
        catch [Text.DecoderFallbackException] { $name = [Text.Encoding]::GetEncoding(1252).GetString($bytes.ToArray()) }
        $path = $name -replace '^\./', ''
        $files[$path] = @{ Size = [long]$keywords['size']; Sha256 = $keywords['sha256digest'] }
    }
    $files
}

function Compare-ExtractedFile {
    <#
    .SYNOPSIS
    Compares what was extracted with what was expected. Returns one string per problem; no output means a match.
    Paths are compared case-insensitively, as NTFS does.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Expected,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Actual
    )

    $actualCi = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in $Actual.GetEnumerator()) { $actualCi[$a.Key] = $a.Value }
    foreach ($e in $Expected.GetEnumerator() | Sort-Object Key) {
        if (-not $actualCi.ContainsKey($e.Key)) { "missing: $($e.Key)"; continue }
        $got = $actualCi[$e.Key]
        if ($got.Size -ne $e.Value.Size) { "size: $($e.Key) is $($got.Size) bytes, expected $($e.Value.Size)" }
        elseif ($e.Value.Sha256 -and $got.Sha256 -ne $e.Value.Sha256) { "content: $($e.Key) has SHA-256 $($got.Sha256), expected $($e.Value.Sha256)" }
        [void]$actualCi.Remove($e.Key)
    }
    foreach ($extra in $actualCi.Keys | Sort-Object) { "unexpected: $extra" }
}

Export-ModuleMember -Function Save-TestArchive, Get-ArchiveFileName, Get-ExpectedFile, ConvertFrom-Mtree, Compare-ExtractedFile
