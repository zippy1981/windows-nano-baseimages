<#
.SYNOPSIS
Pester 5 tests for the Visual C++ runtime checks in images/nanoserver-base/Redistributable.psm1 (issue 14).

.DESCRIPTION
The name tests run anywhere. The metadata tests need Windows with the Visual C++ redistributable installed, as on
GitHub's windows-latest runners, and are skipped elsewhere. Each allowlisted DLL in redistributables.json must pass
both checks, and copies that are renamed, re-labelled or tampered with must fail them.

.EXAMPLE
Invoke-Pester -Path tests/Redistributable.Tests.ps1 -Output Detailed
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables set in BeforeDiscovery and BeforeAll are used in the It blocks, which PSScriptAnalyzer cannot follow')]
param()

BeforeDiscovery {
    $imageDir = Join-Path $PSScriptRoot '../images/nanoserver-base'
    $allowlist = @((Get-Content -Raw (Join-Path $imageDir 'redistributables.json') | ConvertFrom-Json).redistributables |
        ForEach-Object { @{ Name = $_.name } })
    $canCheckMetadata = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../images/nanoserver-base/Redistributable.psm1') -Force
    # Discovery's variables don't reach the run phase, so the names are read again here
    $allowedNames = @((Get-Content -Raw (Join-Path $PSScriptRoot '../images/nanoserver-base/redistributables.json') |
        ConvertFrom-Json).redistributables | ForEach-Object { $_.name })
    $system32 = [Environment]::GetFolderPath('System')
    $work = Join-Path ([IO.Path]::GetTempPath()) "redistributable-tests-$([guid]::NewGuid().ToString('n'))"
    New-Item -ItemType Directory -Path $work | Out-Null
}

AfterAll {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Describe 'The allowlist' {
    It 'is not empty and has no duplicates' {
        $names = $allowedNames
        $names | Should -Not -BeNullOrEmpty
        @($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }
}

Describe 'Test-RedistributableName' {
    It 'accepts the allowlisted <Name>' -ForEach $allowlist {
        Test-RedistributableName -Name $Name | Should -BeTrue
    }

    It 'accepts <Name>' -ForEach @(
        @{ Name = 'vcruntime140.dll' }, @{ Name = 'vcruntime140_1.dll' }, @{ Name = 'msvcp140_2.dll' },
        @{ Name = 'vcomp140.dll' }, @{ Name = 'concrt140.dll' }, @{ Name = 'msvcr120.dll' }, @{ Name = 'MSVCP140.DLL' }
    ) {
        Test-RedistributableName -Name $Name | Should -BeTrue
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'kernel32.dll' }, @{ Name = 'msvcrt.dll' }, @{ Name = 'msvcp_win.dll' }, @{ Name = 'vcruntime.dll' },
        @{ Name = 'msvcp140_atomic_wait.dll' }, @{ Name = 'vcruntime140_1_clr0400.dll' }, @{ Name = 'vcruntime140.exe' },
        @{ Name = 'vcruntime140.dll.bak' }, @{ Name = 'xvcruntime140.dll' }, @{ Name = 'vcruntime140_.dll' },
        @{ Name = 'vcruntime140_1_2.dll' }, @{ Name = 'sub\vcruntime140.dll' }, @{ Name = "vcruntime140.dll`n" }
    ) {
        Test-RedistributableName -Name $Name | Should -BeFalse
    }
}

Describe 'Get-RedistributableProblem' -Skip:(-not $canCheckMetadata) {
    It 'passes the allowlisted <Name> from System32' -ForEach $allowlist {
        $path = Join-Path $system32 $Name
        if (-not (Test-Path $path)) { Set-ItResult -Skipped -Because "$Name is not installed on this machine" }
        Get-RedistributableProblem -Path $path | Should -BeNullOrEmpty
    }

    It 'fails <Name> copied under a name that is not allowed' -ForEach $allowlist {
        $path = Join-Path $system32 $Name
        if (-not (Test-Path $path)) { Set-ItResult -Skipped -Because "$Name is not installed on this machine" }
        $copy = Join-Path $work "renamed-$Name"
        Copy-Item $path $copy
        $problems = @(Get-RedistributableProblem -Path $copy) -join "`n"
        $problems | Should -Match "doesn't match"
        $problems | Should -Match 'OriginalFilename'
    }

    It 'fails <Name> with one byte changed' -ForEach $allowlist {
        $path = Join-Path $system32 $Name
        if (-not (Test-Path $path)) { Set-ItResult -Skipped -Because "$Name is not installed on this machine" }
        $dir = New-Item -ItemType Directory -Path (Join-Path $work "tampered-$([guid]::NewGuid().ToString('n'))")
        $copy = Join-Path $dir $Name
        $bytes = [IO.File]::ReadAllBytes($path)
        # A byte in the middle of the code, well past the headers and before the signature at the end
        $bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0xFF
        [IO.File]::WriteAllBytes($copy, $bytes)
        (@(Get-RedistributableProblem -Path $copy) -join "`n") | Should -Match 'Authenticode signature is HashMismatch'
    }

    It 'fails a Microsoft-signed system DLL renamed to an allowed name' {
        # kernel32.dll is Microsoft's and signed, but its OriginalFilename gives the rename away
        $dir = New-Item -ItemType Directory -Path (Join-Path $work 'impostor')
        $copy = Join-Path $dir 'msvcr999.dll'
        Copy-Item (Join-Path $system32 'kernel32.dll') $copy
        (@(Get-RedistributableProblem -Path $copy) -join "`n") | Should -Match 'OriginalFilename'
    }

    It 'fails a file that is not a signed PE with a version resource' {
        $dir = New-Item -ItemType Directory -Path (Join-Path $work 'unsigned')
        $copy = Join-Path $dir 'vcruntime140.dll'
        [IO.File]::WriteAllBytes($copy, [byte[]](0x4D, 0x5A) + [byte[]]::new(4096))
        $problems = @(Get-RedistributableProblem -Path $copy) -join "`n"
        $problems | Should -Match 'CompanyName'
        $problems | Should -Match 'ProductName'
        $problems | Should -Match 'Authenticode signature is (?!Valid)'
    }
}

Describe 'Copy-Redistributable' -Skip:(-not $canCheckMetadata) {
    It 'copies every allowlisted DLL that passes' {
        $names = @($allowedNames | Where-Object { Test-Path (Join-Path $system32 $_) })
        if (-not $names) { Set-ItResult -Skipped -Because 'no allowlisted DLL is installed on this machine' }
        $dest = Join-Path $work 'copied'
        Copy-Redistributable -Name $names -Source $system32 -Destination $dest | Should -HaveCount $names.Count
        foreach ($n in $names) { Join-Path $dest $n | Should -Exist }
    }

    It 'copies nothing when one name is not allowed' {
        $dest = Join-Path $work 'refused-name'
        { Copy-Redistributable -Name 'vcruntime140.dll', 'kernel32.dll' -Source $system32 -Destination $dest } |
            Should -Throw "*kernel32.dll: the name doesn't match*"
        $dest | Should -Not -Exist
    }

    It 'copies nothing when one file fails the metadata check' {
        $source = New-Item -ItemType Directory -Path (Join-Path $work 'bad-source')
        Copy-Item (Join-Path $system32 'kernel32.dll') (Join-Path $source 'msvcr999.dll')
        $dest = Join-Path $work 'refused-metadata'
        { Copy-Redistributable -Name 'msvcr999.dll' -Source $source -Destination $dest } | Should -Throw '*OriginalFilename*'
        $dest | Should -Not -Exist
    }

    It 'fails when a DLL is not the expected version' {
        $name = @($allowedNames | Where-Object { Test-Path (Join-Path $system32 $_) }) | Select-Object -First 1
        if (-not $name) { Set-ItResult -Skipped -Because 'no allowlisted DLL is installed on this machine' }
        { Copy-Redistributable -Name $name -Source $system32 -Destination (Join-Path $work 'refused-version') -ExpectedVersion '0.0.0.0' } |
            Should -Throw '*not 0.0.0.0*'
    }

    It 'fails when a DLL is missing' {
        $empty = New-Item -ItemType Directory -Path (Join-Path $work 'empty')
        { Copy-Redistributable -Name 'vcruntime140.dll' -Source $empty -Destination (Join-Path $work 'refused-missing') } |
            Should -Throw '*not found*'
    }
}
