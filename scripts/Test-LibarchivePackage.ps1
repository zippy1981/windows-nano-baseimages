<#
.SYNOPSIS
    Smoke-tests a libarchive Windows package made by scripts/build-libarchive.sh.

.DESCRIPTION
    Expands one of the libarchive-X.Y.Z-windows-x64-*.zip packages and runs its tools with PATH limited
    to the Windows system folders, so a DLL missing from the package can't be found elsewhere:

    - bsdtar --version reports the expected libarchive version and every compression library.
    - bsdtar writes, lists and extracts an archive in each format and filter (gzip, bzip2, xz, zstd,
      lz4, zip, AES-256 encrypted zip, 7-Zip, XAR, cpio, ISO9660, ustar, pax), and the extracted files
      match the originals byte for byte.
    - bsdcpio, bsdcat and (when packaged) bsdunzip run.

    With -NanoServerImage it also runs bsdtar inside that Nano Server container, with process
    isolation, which checks the tools need nothing Nano Server lacks.

.PARAMETER PackagePath
    The package zip.

.PARAMETER ExpectedVersion
    The libarchive version, X.Y.Z, that bsdtar must report.

.PARAMETER NanoServerImage
    Optional. A Nano Server image whose version matches the host, for example
    mcr.microsoft.com/windows/nanoserver:ltsc2022.

.PARAMETER WorkDirectory
    Where to expand the package and write test archives. A new folder is made in it and removed
    afterwards. Defaults to the temp folder. Give a path without 8.3 short names when using
    -NanoServerImage, because Docker can't bind-mount those (on GitHub runners, $env:RUNNER_TEMP).

.EXAMPLE
    ./scripts/Test-LibarchivePackage.ps1 -PackagePath out/libarchive-3.8.11-windows-x64-static-tools.zip -ExpectedVersion 3.8.11

.EXAMPLE
    ./scripts/Test-LibarchivePackage.ps1 -PackagePath out/libarchive-3.8.11-windows-x64-shared.zip -ExpectedVersion 3.8.11 -NanoServerImage mcr.microsoft.com/windows/nanoserver:ltsc2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $PackagePath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string] $ExpectedVersion,

    [string] $NanoServerImage,

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $WorkDirectory = [System.IO.Path]::GetTempPath()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Tool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $ArgumentList = @()
    )
    $output = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        throw ('{0} {1} exited with {2}: {3}' -f (Split-Path -Leaf $FilePath), ($ArgumentList -join ' '), $LASTEXITCODE, ($output -join "`n"))
    }
    $output
}

function Get-TreeHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
        '{0} {1}' -f $_.FullName.Substring($Path.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
}

$work = Join-Path $WorkDirectory ('libarchive-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$savedPath = $env:PATH
$failures = [System.Collections.Generic.List[string]]::new()

try {
    Expand-Archive -LiteralPath $PackagePath -DestinationPath (Join-Path $work 'pkg')
    $bsdtar = Get-ChildItem -Path (Join-Path $work 'pkg') -Recurse -Filter 'bsdtar.exe' | Select-Object -First 1
    if (-not $bsdtar) { throw "No bsdtar.exe in $PackagePath" }
    $binDir = $bsdtar.DirectoryName
    foreach ($exe in Get-ChildItem -LiteralPath $binDir -Filter '*.exe') {
        $magic = [System.IO.File]::ReadAllBytes($exe.FullName)[0..1]
        if ($magic[0] -ne 0x4D -or $magic[1] -ne 0x5A) { throw "$($exe.Name) does not start with MZ" }
    }

    # Only the package's own folder (searched first by Windows) and the system folders.
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $tar = $bsdtar.FullName

    $versionText = (Invoke-Tool $tar '--version') -join ' '
    Write-Output "bsdtar --version: $versionText"
    foreach ($needle in @("libarchive $ExpectedVersion", 'zlib/', 'liblzma/', 'bz2lib/', 'liblz4/', 'libzstd/')) {
        if ($versionText -notlike "*$needle*") { $failures.Add("bsdtar --version lacks '$needle'") }
    }

    # Test data: text, a 1 MiB random file, an empty file and a subfolder.
    $data = Join-Path $work 'data'
    New-Item -ItemType Directory -Path (Join-Path $data 'sub') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'hello.txt') -Value ('hello from libarchive ' + $ExpectedVersion) -NoNewline
    $bytes = [byte[]]::new(1MB)
    [System.Random]::new(42).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes((Join-Path $data 'sub\random.bin'), $bytes)
    New-Item -ItemType File -Path (Join-Path $data 'sub\empty.txt') | Out-Null
    $expected = Get-TreeHash $data

    $cases = [ordered]@{
        'tar.gz'      = @('-z')
        'tar.bz2'     = @('-j')
        'tar.xz'      = @('-J')
        'tar.zst'     = @('--zstd')
        'tar.lz4'     = @('--lz4')
        'pax'         = @('--format', 'pax')
        'ustar'       = @('--format', 'ustar')
        'cpio'        = @('--format', 'cpio')
        'zip'         = @('--format', 'zip')
        'aes.zip'     = @('--format', 'zip', '--options', 'zip:encryption=aes256', '--passphrase', 'smoke-test')
        '7z'          = @('--format', '7zip')
        'xar'         = @('--format', 'xar')
        'iso'         = @('--format', 'iso9660')
    }
    foreach ($case in $cases.GetEnumerator()) {
        $archive = Join-Path $work ('test.' + $case.Key)
        $out = Join-Path $work ('out-' + $case.Key)
        New-Item -ItemType Directory -Path $out | Out-Null
        try {
            $create = @('-c', '-f', $archive) + $case.Value + @('-C', $data, '.')
            Invoke-Tool $tar $create | Out-Null
            $read = @()
            if ($case.Key -eq 'aes.zip') { $read = @('--passphrase', 'smoke-test') }
            Invoke-Tool $tar (@('-t', '-f', $archive) + $read) | Out-Null
            Invoke-Tool $tar (@('-x', '-f', $archive, '-C', $out) + $read) | Out-Null
            $actual = Get-TreeHash $out
            if (Compare-Object $expected $actual) {
                $failures.Add("$($case.Key): extracted files differ from the originals")
            }
            else {
                Write-Output "ok   $($case.Key)"
            }
        }
        catch {
            $failures.Add("$($case.Key): $($_.Exception.Message)")
        }
    }

    foreach ($tool in 'bsdcpio', 'bsdcat', 'bsdunzip') {
        $exe = Join-Path $binDir "$tool.exe"
        if (-not (Test-Path -LiteralPath $exe)) {
            if ($tool -ne 'bsdunzip') { $failures.Add("$tool.exe is missing") }
            continue
        }
        try {
            switch ($tool) {
                'bsdcpio' { Write-Output ("bsdcpio --version: " + ((Invoke-Tool $exe '--version') -join ' ')) }
                'bsdcat' {
                    $gz = Join-Path $work 'hello.txt.gz'
                    Invoke-Tool $tar @('-c', '-f', $gz, '--format', 'raw', '-z', '-C', $data, 'hello.txt') | Out-Null
                    $text = (Invoke-Tool $exe $gz) -join ''
                    if ($text -ne ('hello from libarchive ' + $ExpectedVersion)) { $failures.Add("bsdcat printed '$text'") } else { Write-Output 'ok   bsdcat' }
                }
                'bsdunzip' { Invoke-Tool $exe @('-l', (Join-Path $work 'test.zip')) | Out-Null; Write-Output 'ok   bsdunzip -l' }
            }
        }
        catch {
            $failures.Add("${tool}: $($_.Exception.Message)")
        }
    }

    if ($NanoServerImage) {
        $env:PATH = $savedPath
        Write-Output "Running bsdtar in $NanoServerImage"
        $script = @(
            '@echo off'
            'C:\pkg\bsdtar.exe --version || exit /b 1'
            'C:\pkg\bsdtar.exe -c -f C:\work\nano.tar.zst --zstd -C C:\work\data . || exit /b 2'
            'C:\pkg\bsdtar.exe -x -f C:\work\nano.tar.zst -C C:\work\nano-out || exit /b 3'
            'C:\pkg\bsdtar.exe -c -f C:\work\nano.7z --format 7zip -C C:\work\data . || exit /b 4'
            'C:\pkg\bsdtar.exe -t -f C:\work\nano.7z || exit /b 5'
        ) -join "`r`n"
        New-Item -ItemType Directory -Path (Join-Path $work 'nano-out') | Out-Null
        Set-Content -LiteralPath (Join-Path $work 'nano.cmd') -Value $script -Encoding ascii
        $dockerArgs = @('run', '--rm', '--isolation', 'process', '-v', "${binDir}:C:\pkg:ro", '-v', "${work}:C:\work",
            $NanoServerImage, 'cmd', '/S', '/C', 'C:\work\nano.cmd')
        try {
            Invoke-Tool 'docker' $dockerArgs | ForEach-Object { Write-Output "  $_" }
            if (Compare-Object $expected (Get-TreeHash (Join-Path $work 'nano-out'))) {
                $failures.Add('Nano Server: extracted files differ from the originals')
            }
            else {
                Write-Output "ok   Nano Server ($NanoServerImage)"
            }
        }
        catch {
            $failures.Add("Nano Server: $($_.Exception.Message)")
        }
    }
}
finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error -Message $_ -ErrorAction Continue }
    throw "$($failures.Count) check(s) failed for $(Split-Path -Leaf $PackagePath)"
}
Write-Output "All checks passed for $(Split-Path -Leaf $PackagePath)"
