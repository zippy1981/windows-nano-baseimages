<#
.SYNOPSIS
The checks a Visual C++ runtime DLL must pass before nanoserver-base ships it, and the copy that applies them.

.DESCRIPTION
Used by the vcredist stage of the nanoserver-base Dockerfile, which runs Windows PowerShell 5.1 on Server Core, and by
tests/Redistributable.Tests.ps1. Keep it compatible with PowerShell 5.1: no ternaries, no ?? and no ?. operators.

A file is shipped only if it passes both checks (issue 14):
 - Its name matches $RedistributableNamePattern.
 - Its version resource names Microsoft (CompanyName "Microsoft Corporation", a ProductName that starts with
   "Microsoft", and an OriginalFilename equal to its name), and it carries a valid Authenticode signature whose signer
   is Microsoft Corporation and whose chain ends at Microsoft Root Certificate Authority 2010 or 2011.
#>

Set-StrictMode -Version 2.0

# The names a redistributable can have: vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll, vcomp140.dll and so on.
$RedistributableNamePattern = '^(vcruntime|msvcp|vcomp|concrt|msvcr)[0-9]+(_[0-9]+)?[.]dll$'

# Microsoft Root Certificate Authority 2010 and 2011, which Microsoft's code-signing certificates chain to
$MicrosoftRootThumbprint = @(
    '3B1EFD3A66EA28B16697394703A72CA340A05BD5'
    '8F43288AD272F3103B6FB1428485EA3014C0BCFE'
)

function Test-RedistributableName {
    <#
    .SYNOPSIS
    Returns whether a file name is one a Visual C++ runtime DLL can have.

    .PARAMETER Name
    The file name, without a directory. Matching ignores case, as Windows does.

    .EXAMPLE
    Test-RedistributableName -Name vcruntime140_1.dll
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    # $ in .NET also matches before a final newline, so the match must also be the whole name
    $Name -match $RedistributableNamePattern -and $Matches[0] -eq $Name
}

function Get-RedistributableProblem {
    <#
    .SYNOPSIS
    Checks a DLL's name, version resource and Authenticode signature, and returns every problem found.

    .DESCRIPTION
    Returns nothing when the file passes. Each problem is one string that names the file, so the caller can report them
    all before failing.

    .PARAMETER Path
    The DLL to check.

    .EXAMPLE
    Get-RedistributableProblem -Path C:\Windows\System32\vcruntime140.dll
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $file = Get-Item -LiteralPath $Path
    $name = $file.Name
    if (-not (Test-RedistributableName -Name $name)) {
        "${name}: the name doesn't match $RedistributableNamePattern"
    }

    $info = $file.VersionInfo
    if ($info.CompanyName -ne 'Microsoft Corporation') {
        "${name}: CompanyName is '$($info.CompanyName)', not 'Microsoft Corporation'"
    }
    if ("$($info.ProductName)" -notmatch '^Microsoft') {
        "${name}: ProductName is '$($info.ProductName)', which doesn't start with Microsoft"
    }
    if ($info.OriginalFilename -ne $name) {
        "${name}: OriginalFilename is '$($info.OriginalFilename)', not '$name'"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid') {
        "${name}: the Authenticode signature is $($signature.Status): $($signature.StatusMessage)"
    }
    elseif ($signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
        "${name}: signed by '$($signature.SignerCertificate.Subject)', not Microsoft Corporation"
    }
    else {
        # Get-AuthenticodeSignature already trusts the chain. This also requires it to end at a Microsoft root, so a
        # certificate that merely says O=Microsoft Corporation under another root doesn't pass. The signature is
        # timestamped, so a signing certificate that has since expired is fine (Get-AuthenticodeSignature checked the
        # timestamp), and revocation was already checked there too.
        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        $chain.ChainPolicy.VerificationFlags = 'IgnoreNotTimeValid'
        $built = $chain.Build($signature.SignerCertificate)
        $root = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
        if (-not $built) {
            "${name}: the signing certificate's chain doesn't build: $(($chain.ChainStatus | ForEach-Object { $_.StatusInformation.Trim() }) -join '; ')"
        }
        elseif ($root.Thumbprint -notin $MicrosoftRootThumbprint) {
            "${name}: the signing certificate chains to '$($root.Subject)' ($($root.Thumbprint)), not a Microsoft code-signing root"
        }
        $chain.Dispose()
    }
}

function Copy-Redistributable {
    <#
    .SYNOPSIS
    Copies the allowlisted Visual C++ runtime DLLs, and fails without copying anything unless every one passes.

    .PARAMETER Name
    The DLL names to copy (the allowlist in redistributables.json).

    .PARAMETER Source
    The folder they are installed in, normally C:\Windows\System32 after the redistributable has run.

    .PARAMETER Destination
    The folder to copy them to. It is created if needed.

    .PARAMETER ExpectedVersion
    When set, each DLL's FileVersion must be this version, so the README's version list stays true.

    .EXAMPLE
    Copy-Redistributable -Name vcruntime140.dll, msvcp140.dll -Source C:\Windows\System32 -Destination C:\vcredist -ExpectedVersion 14.51.36247.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Name,

        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination,

        [string] $ExpectedVersion
    )

    $problems = New-Object Collections.Generic.List[string]
    foreach ($n in $Name) {
        $path = Join-Path $Source $n
        if (-not (Test-RedistributableName -Name $n)) {
            $problems.Add("${n}: the name doesn't match $RedistributableNamePattern")
        }
        elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $problems.Add("${n}: not found in $Source")
        }
        else {
            foreach ($p in @(Get-RedistributableProblem -Path $path)) { $problems.Add($p) }
            $version = (Get-Item -LiteralPath $path).VersionInfo.FileVersion
            if ($ExpectedVersion -and $version -ne $ExpectedVersion) {
                $problems.Add("${n}: FileVersion is $version, not $ExpectedVersion")
            }
        }
    }
    if ($problems.Count) {
        throw ("Refusing to copy the redistributables:`n" + ($problems -join "`n"))
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($n in $Name) {
        Copy-Item -LiteralPath (Join-Path $Source $n) -Destination $Destination
        $v = (Get-Item -LiteralPath (Join-Path $Destination $n)).VersionInfo
        Write-Verbose "Copied $n $($v.FileVersion)"
        # One line per DLL, for the build log
        '{0} {1}' -f $n, $v.FileVersion
    }
}

Export-ModuleMember -Variable RedistributableNamePattern -Function Test-RedistributableName, Get-RedistributableProblem, Copy-Redistributable
