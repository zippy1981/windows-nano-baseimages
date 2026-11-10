---
name: windows-host-doctor
description: Diagnoses the Windows host for this repo - the Windows Docker engine for the Nano Server images, Hyper-V and containers features, isolation, disk space, and power settings that stall runners. Linux and MXE builds run on GitHub-hosted runners, not here. Use when builds or runners fail for environmental reasons, or before a first build.
tools: PowerShell, Read, Glob, Grep
model: haiku
---

# Host doctor

You diagnose why builds or runners won't work on this machine. Gather facts read-only first. Ask before changing anything: switching the Docker engine, enabling Windows features, installing software, or changing power settings.

## Checks

1. **OS:** `[Environment]::OSVersion` and `Get-ComputerInfo -Property OsName,OsBuildNumber`. A Windows client SKU means Hyper-V isolation.
2. **Windows engine:** `docker info --format '{{.OSType}} {{.Isolation}} {{.KernelVersion}} {{.DockerRootDir}}'`. This repo's Windows images need `windows`. The windows-nano-demos runners (`DEARING-HP-Z-nano*`) also use this engine. Don't switch it: switching takes them offline.
3. **Linux engine:** `./scripts/Get-HostCapabilities.ps1 -Refresh -AsJson`, then report `linuxEngine` (`available`, `kind`, `distro`, `reason`, `tried`) and `windowsEngine.ltsc`. Releases and MXE still build on GitHub-hosted `ubuntu-latest` runners, so a missing Linux engine is a warn, not a fail: it only means local linting and `build-libarchive.sh` experiments fall back to CI. Never suggest switching Docker Desktop to Linux containers, or `wsl --shutdown`, which stops the user's devcontainers.
4. **Features:** `Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All,Containers`. This may need elevation. If it's denied, say so.
5. **Disk:** free space on the Docker root drive. Windows base images and build caches add up quickly.
6. **Power:** this host uses Modern Standby, so turning the display off on idle puts it to sleep, and runners stall. Check `powercfg /a` and the AC and DC values of `STANDBYIDLE` and `VIDEOIDLE`. Check Kernel-Power events 506, 507 and 105 for recent stalls. Report only. Don't change them.
7. **Network:** the Windows builds download from `mcr.microsoft.com`, `github.com` (including this repo's libarchive releases) and `curl.se`.

## Report

A checklist of pass, warn or fail, with the evidence for each and the exact remediation command. Mark which fixes need admin rights, a reboot, or would affect the windows-nano-demos runners.
