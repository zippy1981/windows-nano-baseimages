---
name: host-capabilities
description: Find out which container engines this host has (a Windows engine for the Nano Server images, a Linux engine such as a WSL distro's own Docker, both, or neither) and route container work to a local engine or to GitHub Actions. Use before any docker command, before building or testing an image, before running Linux tools such as shellcheck or actionlint in a container, or when asked whether this machine can run Linux or Windows containers.
---

# Host capabilities

Claude Code runs on Windows hosts (some with WSL), on Linux and macOS, inside WSL, and in cloud sandboxes. Don't assume which engines exist. Read the probe's report, then follow the routing table. The policy is in [ADR 0010](../../../docs/adr/0010-route-container-work-by-probed-host-capabilities.md).

## 1. Read the report

| Shell | Command |
| --- | --- |
| PowerShell (Windows) | `./scripts/Get-HostCapabilities.ps1 -AsJson` |
| Bash or sh (any OS; Git Bash hands off to the PowerShell script) | `scripts/host-capabilities.sh` |

A cached report is reused for 24 hours, so it's cheap to read again. Probe again (`-Refresh`, or `--refresh` for the sh script) when a docker command can't reach its engine, when the user says something on the host changed, or before telling the user the host can't do something. On Windows a fresh probe boots WSL distros, one after another, until one has a working Docker.

The fields that decide things:

| Field | Meaning |
| --- | --- |
| `platform` | `windows`, `wsl` (Claude is running inside WSL), `linux` or `macos` |
| `windowsEngine.available`, `.invoke` | Whether a Windows engine answers, and the command that reaches it (`docker`, or `docker.exe` from inside WSL) |
| `windowsEngine.ltsc.<2019\|2022\|2025>.isolation` | `process`, `hyperv`, or `null` when that version can't run here. Only filled in on Windows. |
| `linuxEngine.available`, `.invoke` | Whether a Linux engine answers, and the command that reaches it, for example `["wsl.exe","--distribution","Ubuntu","--exec","docker"]` |
| `linuxEngine.repoPath` | This checkout's path as the Linux engine's host sees it, for bind mounts |
| `linuxEngine.containers` minus `.claudeContainers` | Containers that belong to someone else (the user's devcontainers). Leave them alone. |
| `linuxEngine.reason`, `.tried` | Why there's no Linux engine, and what was tried |
| `policy.sharedHost` | `true` unless the user overrode it. Shared means strict cleanup (section 4). |
| `github.authenticated` | Whether `gh` can dispatch workflows |

## 2. Route the task

| Task | Run locally when | Otherwise |
| --- | --- | --- |
| Build or test a Nano Server image | `windowsEngine.available`, and that version's `isolation` isn't `null`. Pass `--isolation <value>` and `--memory 4g`. | `nanoserver-base.yml` on this repo's self-hosted runners (ADR 0008). A PR that touches `images/` runs it. |
| Try a change to `scripts/build-libarchive.sh` | `linuxEngine.available`, using the MXE image from `scripts/mxe-image-tag.sh` | `build-libarchive.yml`, which also runs on a push that touches the script |
| A libarchive release, or the MXE image itself | Never locally. Releases come from CI, and MXE takes hours. | `build-libarchive.yml` or `mxe-image.yml` |
| shellcheck or actionlint | `linuxEngine.available`, with the tool version `lint-scripts.yml` uses | `lint-scripts.yml`, which runs on every push |
| PSScriptAnalyzer or Pester | Any host with `pwsh`. No container needed. | `lint-scripts.yml` |

Dispatching a workflow is outward-facing, so ask before `gh workflow run`. If `github.authenticated` is false, ask the user to run `! gh auth login`. Never handle tokens.

## 3. Run on the engine

Use `invoke` exactly as the report gives it, with the docker arguments after it.

```pwsh
$linux = (./scripts/Get-HostCapabilities.ps1).linuxEngine
& $linux.invoke[0] @($linux.invoke | Select-Object -Skip 1) run --rm --name claude-lint-3f9a `
    --label com.zippy1981.created-by=claude-code --label com.zippy1981.session=3f9a `
    --volume "$($linux.repoPath):/src:ro" --workdir /src rhysd/actionlint:1.7.12 -color
```

- **Prefer PowerShell on Windows.** Git Bash rewrites arguments that look like paths (`/src` becomes `C:/Program Files/Git/src`), so in Bash prefix the command with `MSYS_NO_PATHCONV=1`.
- **`--exec` runs docker without a shell** inside the distro. Don't pass `bash -lc '...'` through `wsl.exe`: the quoting breaks and `$variables` are expanded in the wrong place.
- **`/mnt/c` is slow.** That's fine for linters and for reading the repo. For a real build, copy the sources into the container or a Linux directory instead of building on the bind mount.
- **Line endings:** `.gitattributes` keeps `*.sh` LF, so the repo's scripts run unchanged in a Linux container from a Windows checkout.
- **GHCR pulls:** if pulling `ghcr.io/zippy1981/mxe-libarchive` is denied, the package is private, and logging in is the user's call.

## 4. Name, label and clean up

On a shared host (`policy.sharedHost`, the default), everything you create carries:

- a name `claude-<task>-<tag>`, where `<tag>` is 4 hex characters you pick once per session
- `--label com.zippy1981.created-by=claude-code --label com.zippy1981.session=<tag>`, on `docker run`, `docker create` and `docker build`

Prefer images that are already present (`docker images`). If you pull one, note that it wasn't there before, and remove exactly that reference when you're done.

Clean up with the `safe-docker-cleanup` skill: `./scripts/Remove-DockerArtifacts.ps1 -Prefix claude-<task>- -Engine Linux`. On the Linux engine it removes only what has both the prefix and the label. Without pwsh, use `docker ps -aq --filter label=com.zippy1981.session=<tag> | xargs -r docker rm -f`.

## 5. When an engine is missing

- **No Linux engine, but WSL is installed** (`linuxEngine.tried` names the distros): offer to install Docker Engine in the distro (`sudo apt-get install docker.io`), or to start its daemon if `tried` says it isn't reachable (`sudo systemctl start docker`). Both are host changes, so ask first. Otherwise, offer the workflow from the routing table.
- **No Linux engine and no WSL** (Windows without WSL, or a Linux or macOS host without Docker): offer the workflow, or report what's missing.
- **No Windows engine** (Linux, macOS, or a cloud sandbox): the Nano Server images can only be built by `nanoserver-base.yml`. Don't try workarounds.

## 6. Never

- Switch Docker Desktop between Windows and Linux containers, on any host. `dockerDesktopSwitch` is always `never`, because switching takes the windows-nano-demos runners offline.
- Run `wsl --shutdown` or `wsl --terminate`. They stop the user's devcontainers.
- Start, stop or reconfigure a daemon, or install software, without asking.
- Touch containers or images you didn't create, on either engine.

## Overrides

Per host, in `.claude/host-capabilities.overrides.local.json`, which is gitignored. It's a flat JSON object. Any key can be left out.

```json
{
  "linuxEngine": "wsl:Ubuntu",
  "sharedHost": true,
  "maxAgeHours": 24
}
```

- `linuxEngine`: `auto` (the default), `none`, `wsl:<distro>` (Windows only), `docker` (the default docker context, if it's a Linux engine), or `docker-desktop-linux` (Windows only: Docker Desktop's Linux engine pipe, if it already exists; it's never switched to)
- `sharedHost`: set `false` only on a host that nothing else uses
- `maxAgeHours`: how long a report is reused

Editing the overrides file invalidates the cache. Reports are kept in `.claude/host-capabilities.<platform>.local.json`, one per platform, so a Windows session and a WSL session on the same checkout don't overwrite each other.
