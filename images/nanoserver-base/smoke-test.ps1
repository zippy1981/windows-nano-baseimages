<#
.SYNOPSIS
Smoke-tests a nanoserver-base image: the tools are found first on PATH, report the pinned versions, load on this
Windows version, and tar extracts every archive in tests/archives.json correctly, from a file and from a pipe.

.DESCRIPTION
Runs on the CI runner (or any Windows Docker host) with PowerShell 7. Everything runs inside one container as
ContainerUser, through a generated run.cmd: the base image has no PowerShell. The runner is itself a container, so
files go in and out with docker cp, never bind mounts.

The archives are downloaded once into -CacheDirectory and checked against their pinned SHA-256. What tar extracts is
recorded in the container as an mtree listing (path, size, SHA-256, computed by bsdtar from the extracted files) and
compared on the runner with the archive's contents as .NET reads them (see tests/ArchiveTest.psm1).

The test fails, with a list of every problem, if any check fails.

.PARAMETER Image
The image to test, for example nanoserver-base:ci-2025-<sha>.

.PARAMETER CacheDirectory
Where the test archives are cached. Defaults to a folder under RUNNER_TOOL_CACHE, which survives between jobs on a
self-hosted runner, or under TEMP.

.PARAMETER Archive
Only test these archives (by name in tests/archives.json). Defaults to all of them.

.PARAMETER SkipArchives
Only check the tools, not the archive extraction.

.EXAMPLE
./images/nanoserver-base/smoke-test.ps1 -Image nanoserver-base:ltsc2025

.EXAMPLE
./images/nanoserver-base/smoke-test.ps1 -Image nanoserver-base:ltsc2019 -Archive far, nano
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
param(
    [Parameter(Mandatory)]
    [string] $Image,

    [string] $CacheDirectory = (Join-Path ($env:RUNNER_TOOL_CACHE ? $env:RUNNER_TOOL_CACHE : $env:TEMP) 'nanoserver-base-test-archives'),

    [string[]] $Archive,

    [switch] $SkipArchives
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $repoRoot 'tests/ArchiveTest.psm1') -Force

# The pinned versions, read from the Dockerfile so they are written down in one place
$dockerfile = Get-Content -Raw (Join-Path $PSScriptRoot 'Dockerfile')
function Get-Pin([string] $Name) {
    if ($dockerfile -notmatch "(?m)\b$Name=(\S+)") { throw "$Name is not set in the Dockerfile" }
    $Matches[1]
}
$pins = @{
    libarchive = Get-Pin 'LIBARCHIVE_VERSION'
    jq = Get-Pin 'JQ_VERSION'
}

$failures = [Collections.Generic.List[string]]::new()
$summary = [Collections.Generic.List[string]]::new()
$ntStatus = @{ '-1073741515' = '0xC0000135 (a DLL is missing)'; '-1073741511' = '0xC0000139 (an entry point is missing)' }

# Each check is one command in run.cmd. Its output goes to C:\r\<name>.out and its exit code to C:\r\<name>.exit.
# (">file echo %ERRORLEVEL%" puts the redirection first, so an exit code of 0-9 isn't read as a handle number.)
$commands = [ordered]@{
    # Nano Server has no whoami.exe or where.exe, so these use cmd itself. %%~$PATH:i is the first match on PATH.
    'user' = 'echo %USERNAME%'
    'path' = 'echo %PATH%'
    'path-tar' = 'for %%i in (tar.exe) do @echo %%~$PATH:i'
    'path-curl' = 'for %%i in (curl.exe) do @echo %%~$PATH:i'
    'tar' = 'tar --version'
    'bsdcpio' = 'bsdcpio --version'
    'bsdcat' = 'bsdcat --version'
    'bsdunzip' = 'bsdunzip --version'
    'curl' = 'curl -V'
    'jq' = 'jq --version'
    'jq-filter' = 'echo {"a":[1,2]}| jq -c .a'
    'edit' = 'edit --version'
    'https' = 'curl -fsSL https://github.com/jqlang/jq/releases/download/jq-1.8.2/sha256sum.txt'
    'licenses' = 'dir /b /s C:\tools\licenses'
}
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('@echo off')
$lines.Add('mkdir C:\r C:\w')
foreach ($c in $commands.GetEnumerator()) {
    $lines.Add("$($c.Value) > C:\r\$($c.Key).out 2>&1")
    $lines.Add(">C:\r\$($c.Key).exit echo %ERRORLEVEL%")
}

$archives = @()
if (-not $SkipArchives) {
    $manifest = Get-Content -Raw (Join-Path $repoRoot 'tests/archives.json') | ConvertFrom-Json
    $archives = @($manifest.archives | Where-Object { -not $Archive -or $_.name -in $Archive })
    if ($Archive -and $archives.Count -ne @($Archive).Count) { throw "Unknown archive in -Archive: $($Archive -join ', ')" }
    Save-TestArchive -Archive $archives -CacheDirectory $CacheDirectory
    foreach ($a in $archives) {
        $file = Get-ArchiveFileName $a
        $modes = [ordered]@{ 'file' = "tar -xf C:\test\archives\$file" }
        if ($a.pipe) { $modes['pipe'] = "curl -fsS file:///C:/test/archives/$file | tar -xf -" }
        foreach ($m in $modes.GetEnumerator()) {
            $id = "$($a.name)-$($m.Key)"
            $dir = "C:\w\$id"
            $lines.Add("mkdir $dir")
            $lines.Add("$($m.Value) -C $dir > C:\r\$id.out 2>&1")
            $lines.Add(">C:\r\$id.exit echo %ERRORLEVEL%")
            # mtree from the extracted files, so every file's size and SHA-256 can be compared on the runner
            $lines.Add("tar -cf C:\r\$id.mtree --format=mtree --options=!all,type,size,sha256 -C $dir .")
            foreach ($exe in @($a.PSObject.Properties['executables'] ? $a.executables : @())) {
                $lines.Add("copy /y `"$dir\$($exe -replace '/', '\')`" C:\r\$id-$(Split-Path -Leaf $exe) > nul")
            }
            $lines.Add("rmdir /s /q $dir")
        }
    }
}

$stage = Join-Path ([IO.Path]::GetTempPath()) "nanoserver-base-smoke-$([guid]::NewGuid().ToString('n'))"
$results = Join-Path $stage 'r'
New-Item -ItemType Directory -Path (Join-Path $stage 'test') | Out-Null
Set-Content -Path (Join-Path $stage 'test/run.cmd') -Value $lines -Encoding ascii
$container = "nanoserver-base-smoke-$([guid]::NewGuid().ToString('n').Substring(0, 12))"

try {
    docker create --name $container --user ContainerUser $Image cmd /S /C C:\test\run.cmd | Out-Null
    if ($LASTEXITCODE) { throw "docker create failed: $LASTEXITCODE" }
    docker cp (Join-Path $stage 'test') "${container}:C:\test"
    if ($LASTEXITCODE) { throw "docker cp of run.cmd failed: $LASTEXITCODE" }
    if ($archives) {
        $archiveStage = Join-Path $stage 'archives'
        New-Item -ItemType Directory -Path $archiveStage | Out-Null
        # Hard links where the cache is on the same volume, so staging doesn't copy a gigabyte
        foreach ($a in $archives) {
            $source = Join-Path $CacheDirectory (Get-ArchiveFileName $a)
            $target = Join-Path $archiveStage (Get-ArchiveFileName $a)
            try { New-Item -ItemType HardLink -Path $target -Target $source | Out-Null } catch { Copy-Item $source $target }
        }
        docker cp $archiveStage "${container}:C:\test\archives"
        if ($LASTEXITCODE) { throw "docker cp of the archives failed: $LASTEXITCODE" }
    }
    $started = Get-Date
    docker start --attach $container
    if ($LASTEXITCODE) { $failures.Add("run.cmd exited with $LASTEXITCODE") }
    Write-Host "Container ran for $([int]((Get-Date) - $started).TotalSeconds) s"
    docker cp "${container}:C:\r" $results
    if ($LASTEXITCODE) { throw "docker cp of the results failed: $LASTEXITCODE" }
}
finally {
    docker rm -f $container 2>$null | Out-Null
}

function Read-Result([string] $Name) {
    $outFile = Join-Path $results "$Name.out"
    $exitFile = Join-Path $results "$Name.exit"
    [pscustomobject]@{
        Output = (Test-Path $outFile) ? @(Get-Content $outFile) : @()
        Exit = (Test-Path $exitFile) ? (Get-Content -Raw $exitFile).Trim() : 'not run'
    }
}

function Test-Command([string] $Name, [string] $Pattern, [string] $Description) {
    $r = Read-Result $Name
    $text = $r.Output -join "`n"
    if ($r.Exit -ne '0') {
        $why = $ntStatus[$r.Exit] ? $ntStatus[$r.Exit] : "exit code $($r.Exit)"
        $failures.Add("${Name}: $($commands[$Name]) failed with $why. Output: $text")
    }
    elseif ($Pattern -and $text -notmatch $Pattern) {
        $failures.Add("${Name}: expected $Description, got: $text")
    }
    $summary.Add("| ``$($commands[$Name])`` | $($r.Exit) | ``$(($r.Output | Select-Object -First 1) -replace '\|', '\|')`` |")
}

$summary.Add('| Command | Exit | First line of output |')
$summary.Add('| --- | --- | --- |')
Test-Command 'user' '(?i)\AContainerUser\s*\z' 'ContainerUser'
Test-Command 'path' '(?i)\AC:\\tools\\bin;' 'C:\tools\bin first on PATH'
Test-Command 'path-tar' '(?i)\AC:\\tools\\bin\\tar\.exe\s*\z' 'C:\tools\bin\tar.exe'
# curl is Windows' own (Schannel), because curl.se's LibreSSL build can't verify HTTPS on Nano Server (issue 5)
Test-Command 'path-curl' '(?i)\AC:\\Windows\\system32\\curl\.exe\s*\z' 'C:\Windows\System32\curl.exe'
foreach ($tool in 'tar', 'bsdcpio', 'bsdcat', 'bsdunzip') {
    $name = ($tool -eq 'tar') ? 'bsdtar' : $tool
    Test-Command $tool "^$name $([regex]::Escape($pins.libarchive)) - libarchive $([regex]::Escape($pins.libarchive)) " "$name $($pins.libarchive)"
}
Test-Command 'curl' '(?i)Schannel' 'curl with Schannel'
Test-Command 'jq' "^jq-$([regex]::Escape($pins.jq))$" "jq-$($pins.jq)"
Test-Command 'jq-filter' '^\[1,2\]$' '[1,2]'
# Edit v2.0.0 reports its own version string (1.2.1), so only the exit code is checked
Test-Command 'edit' '' ''
Test-Command 'https' 'jq-windows-amd64\.exe' 'the jq sha256sum.txt over HTTPS'
Test-Command 'licenses' '(?s)libarchive.*libiconv-[\d.]+\.tar\.gz' 'licence files including the libiconv source'
foreach ($tool in 'libarchive', 'jq', 'edit') {
    if (-not ((Read-Result 'licenses').Output -match "(?i)^C:\\tools\\licenses\\$tool\\")) { $failures.Add("licenses: nothing in C:\tools\licenses\$tool") }
}
$curlInfo = (Read-Result 'curl').Output
$summary.Add('')
$summary.Add("curl TLS and features: ``$($curlInfo | Select-Object -First 1)`` / ``$($curlInfo | Where-Object { $_ -like 'Features:*' })``")

if ($archives) {
    $summary.Add('')
    $summary.Add('| Archive | Row | Mode | Exit | Files | Result |')
    $summary.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($a in $archives) {
        $expected = Get-ExpectedFile -Entry $a -CacheDirectory $CacheDirectory -ExpectedDirectory (Join-Path $repoRoot 'tests/expected')
        foreach ($mode in @('file') + @($a.pipe ? 'pipe' : @())) {
            $id = "$($a.name)-$mode"
            $r = Read-Result $id
            $mtree = Join-Path $results "$id.mtree"
            $actual = (Test-Path $mtree) ? (ConvertFrom-Mtree -Line @(Get-Content $mtree)) : @{}
            $problems = @(Compare-ExtractedFile -Expected $expected -Actual $actual)
            if ($r.Exit -ne '0') { $problems = @("tar exited with $($r.Exit): $($r.Output -join ' ')") + $problems }
            foreach ($req in @($a.PSObject.Properties['required'] ? $a.required : @())) {
                if (-not $actual.ContainsKey($req)) { $problems += "required file missing: $req" }
            }
            foreach ($exe in @($a.PSObject.Properties['executables'] ? $a.executables : @())) {
                $copy = Join-Path $results "$id-$(Split-Path -Leaf $exe)"
                $head = (Test-Path $copy) ? [IO.File]::ReadAllBytes($copy)[0..1] : @()
                if (-not ($head.Count -eq 2 -and $head[0] -eq 0x4D -and $head[1] -eq 0x5A)) { $problems += "$exe does not start with MZ" }
            }
            # Known failures are strict, like a strict xfail: the recorded symptom must appear, and once the failure
            # is gone the test fails until the entry is removed from tests/archives.json.
            #  - expectedFailure on an archive (Deflate64, issue 7): tar fails loudly, with output matching .output
            #  - pipeExpectedFailure for every piped zip (issue 8): tar exits 0 but files are missing
            $xfail = $a.PSObject.Properties['expectedFailure'] ? $a.expectedFailure :
                ($mode -eq 'pipe' -and $manifest.PSObject.Properties['pipeExpectedFailure'] ? $manifest.pipeExpectedFailure : $null)
            if ($xfail) {
                $symptom = $xfail.PSObject.Properties['output'] ?
                    ($r.Exit -ne '0' -and ($r.Output -join "`n") -match $xfail.output) :
                    [bool]($problems -match '^(missing|required file missing): ')
                $problems = if (-not $problems) { @("passes now, so remove the expected failure for issue $($xfail.issue) from tests/archives.json") }
                    elseif (-not $symptom) { @("failed, but not with the known symptom of issue $($xfail.issue) ($($xfail.reason))") + $problems }
                    else { @() }
            }
            $result = $problems ? "**FAIL** ($($problems.Count) problems)" : ($xfail ? "expected failure (#$($xfail.issue))" : 'ok')
            $summary.Add("| $($a.name) | $($a.PSObject.Properties['row'] ? $a.row : 'regression') | $mode | $($r.Exit) | $($actual.Count) of $($expected.Count) | $result |")
            foreach ($p in $problems | Select-Object -First 20) { $failures.Add("${id}: $p") }
            if ($problems.Count -gt 20) { $failures.Add("${id}: ... and $($problems.Count - 20) more") }
        }
    }
}

$report = @("### Smoke test: $Image", '') + $summary
$report | ForEach-Object { Write-Host $_ }
if ($env:GITHUB_STEP_SUMMARY) { $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "::error::$_" }
    throw "$($failures.Count) smoke test failures in $Image"
}
Write-Host "All smoke tests passed for $Image"
