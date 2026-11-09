<#
.SYNOPSIS
Builds a throwaway image FROM a nanoserver-base image with PHP, MySQL and Helix, and checks that they run, so the
base's Visual C++ runtime DLLs are proven to be enough for real programs (issue 14).

.DESCRIPTION
Runs on the CI runner (or any Windows Docker host) with PowerShell 7. tests/downstream/Dockerfile adds the three
programs and no DLLs of its own. Everything then runs inside one container as ContainerUser, through a generated
run.cmd, and the results come back with docker cp: the runner is itself a container, so there are no bind mounts.

Checks: php -v; PHP loads curl, intl (whose ICU DLLs need msvcp140.dll and vcruntime140_1.dll), mbstring, openssl and
zip without warnings; mysqld and mysql report their version; mysqld initializes a data directory; hx reports its
version. No program may fail with 0xC0000135 (a DLL is missing) or 0xC0000139 (an entry point is missing).

The test image is removed afterwards unless -KeepImage is set. The test fails, with a list of every problem, if any
check fails.

.PARAMETER BaseImage
The nanoserver-base image to test, for example nanoserver-base:ci-2025-<sha>.

.PARAMETER WindowsVersion
The LTSC version of BaseImage: 2019, 2022 or 2025. It picks the Server Core download image when -DownloadImage
isn't set.

.PARAMETER DownloadImage
The Server Core image for the download stage. CI passes the digest it pinned.

.PARAMETER KeepImage
Leave the test image in place, tagged nanoserver-base-downstream-test:<random>, for debugging.

.EXAMPLE
./tests/downstream/smoke-test.ps1 -BaseImage nanoserver-base:ltsc2025 -WindowsVersion 2025

.EXAMPLE
./tests/downstream/smoke-test.ps1 -BaseImage $env:IMAGE -WindowsVersion $env:WINDOWS_VERSION -DownloadImage $env:SERVERCORE_IMAGE
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'CI log output and GitHub workflow commands (::error::) go to the host on purpose')]
param(
    [Parameter(Mandatory)]
    [string] $BaseImage,

    [Parameter(Mandatory)]
    [ValidateSet('2019', '2022', '2025')]
    [string] $WindowsVersion,

    [string] $DownloadImage = "mcr.microsoft.com/windows/servercore:ltsc$WindowsVersion-amd64",

    [switch] $KeepImage
)

$ErrorActionPreference = 'Stop'

# The pinned versions, read from the Dockerfile so they are written down in one place
$dockerfile = Get-Content -Raw (Join-Path $PSScriptRoot 'Dockerfile')
function Get-Pin([string] $Name) {
    if ($dockerfile -notmatch "(?m)\b$Name=(\S+)") { throw "$Name is not set in the Dockerfile" }
    $Matches[1]
}
$php = (Get-Pin 'PHP_VERSION') -replace '-\d+$'
$mysql = Get-Pin 'MYSQL_VERSION'
$helix = Get-Pin 'HELIX_VERSION'

$id = [guid]::NewGuid().ToString('n').Substring(0, 12)
$image = "nanoserver-base-downstream-test:$id"
$container = "nanoserver-base-downstream-$id"
$stage = Join-Path ([IO.Path]::GetTempPath()) "nanoserver-base-downstream-$id"
$results = Join-Path $stage 'r'
$failures = [Collections.Generic.List[string]]::new()
$summary = [Collections.Generic.List[string]]::new()
$ntStatus = @{ '-1073741515' = '0xC0000135 (a DLL is missing)'; '-1073741511' = '0xC0000139 (an entry point is missing)' }

# Each check is one command in run.cmd. Its output goes to C:\r\<name>.out and its exit code to C:\r\<name>.exit.
# (">file echo %ERRORLEVEL%" puts the redirection first, so an exit code of 0-9 isn't read as a handle number.)
$extensions = 'curl', 'intl', 'mbstring', 'openssl', 'zip'
$commands = [ordered]@{
    'user' = 'echo %USERNAME%'
    'php' = 'C:\php\php.exe -v'
    'php-extensions' = "C:\php\php.exe -r `"echo 'missing=', implode(',', array_diff(['$($extensions -join "','")'], get_loaded_extensions())), ' icu=', INTL_ICU_VERSION, PHP_EOL;`""
    'mysqld' = 'C:\mysql\bin\mysqld.exe --version'
    'mysql' = 'C:\mysql\bin\mysql.exe --version'
    'mysqld-initialize' = 'C:\mysql\bin\mysqld.exe --no-defaults --initialize-insecure --basedir=C:\mysql --datadir=C:\w\mysql-data --console'
    'hx' = 'C:\helix\hx.exe --version'
}
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('@echo off')
$lines.Add('mkdir C:\r C:\w')
foreach ($c in $commands.GetEnumerator()) {
    $lines.Add("$($c.Value) > C:\r\$($c.Key).out 2>&1")
    $lines.Add(">C:\r\$($c.Key).exit echo %ERRORLEVEL%")
}

try {
    $started = Get-Date
    # Hyper-V isolated builds default to 1 GB of memory
    docker build --memory 4g --build-arg WINDOWS_VERSION=$WindowsVersion --build-arg BASE_IMAGE=$BaseImage `
        --build-arg DOWNLOAD_IMAGE=$DownloadImage -t $image $PSScriptRoot
    if ($LASTEXITCODE) { throw "docker build of the downstream test image failed: $LASTEXITCODE" }
    Write-Host "Built $image in $([int]((Get-Date) - $started).TotalSeconds) s"

    New-Item -ItemType Directory -Path (Join-Path $stage 'test') | Out-Null
    Set-Content -Path (Join-Path $stage 'test/run.cmd') -Value $lines -Encoding ascii
    docker create --name $container --user ContainerUser $image cmd /S /C C:\test\run.cmd | Out-Null
    if ($LASTEXITCODE) { throw "docker create failed: $LASTEXITCODE" }
    docker cp (Join-Path $stage 'test') "${container}:C:\test"
    if ($LASTEXITCODE) { throw "docker cp of run.cmd failed: $LASTEXITCODE" }
    docker start --attach $container
    if ($LASTEXITCODE) { $failures.Add("run.cmd exited with $LASTEXITCODE") }
    docker cp "${container}:C:\r" $results
    if ($LASTEXITCODE) { throw "docker cp of the results failed: $LASTEXITCODE" }
}
finally {
    docker rm -f $container 2>$null | Out-Null
    # --no-prune keeps the untagged layers, which are the build cache for the next run on this daemon
    if (-not $KeepImage) { docker rmi -f --no-prune $image 2>$null | Out-Null }
}

function Test-Command([string] $Name, [string] $Pattern, [string] $Description) {
    $outFile = Join-Path $results "$Name.out"
    $exitFile = Join-Path $results "$Name.exit"
    $output = (Test-Path $outFile) ? @(Get-Content $outFile) : @()
    $exit = (Test-Path $exitFile) ? (Get-Content -Raw $exitFile).Trim() : 'not run'
    $text = $output -join "`n"
    if ($exit -ne '0') {
        $why = $ntStatus[$exit] ? $ntStatus[$exit] : "exit code $exit"
        $failures.Add("${Name}: $($commands[$Name]) failed with $why. Output: $text")
    }
    elseif ($Pattern -and $text -notmatch $Pattern) {
        $failures.Add("${Name}: expected $Description, got: $text")
    }
    $summary.Add("| ``$Name`` | $exit | ``$(($output | Where-Object { $_.Trim() } | Select-Object -First 1) -replace '\|', '\|')`` |")
}

$summary.Add('| Check | Exit | First line of output |')
$summary.Add('| --- | --- | --- |')
Test-Command 'user' '(?i)\AContainerUser\s*\z' 'ContainerUser'
Test-Command 'php' "^PHP $([regex]::Escape($php)) " "PHP $php"
# A warning means an extension failed to load, often because a DLL it needs is missing
Test-Command 'php-extensions' '(?s)\A(?!.*Warning)missing= icu=\d+' "every extension in [$($extensions -join ', ')] loaded, without warnings"
Test-Command 'mysqld' "Ver $([regex]::Escape($mysql)) " "mysqld $mysql"
Test-Command 'mysql' "Ver $([regex]::Escape($mysql)) " "mysql $mysql"
Test-Command 'mysqld-initialize' '(?s)\A(?!.*\[ERROR\]).*root@localhost is created with an empty password' 'a data directory initialized without errors'
Test-Command 'hx' "^helix $([regex]::Escape($helix))\b" "helix $helix"

$report = @("### Downstream smoke test: PHP $php, MySQL $mysql and Helix $helix on $BaseImage", '') + $summary
$report | ForEach-Object { Write-Host $_ }
if ($env:GITHUB_STEP_SUMMARY) { $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "::error::$_" }
    throw "$($failures.Count) downstream smoke test failures on $BaseImage"
}
Write-Host "All downstream smoke tests passed on $BaseImage"
