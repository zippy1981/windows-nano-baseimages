# 0010. Route container work by probed host capabilities

- Status: Proposed
- Date: 2026-11-10
- Deciders: zippy1981
- Related: [host-capabilities skill](../../.claude/skills/host-capabilities/SKILL.md), [scripts/Get-HostCapabilities.ps1](../../scripts/Get-HostCapabilities.ps1), [scripts/host-capabilities.sh](../../scripts/host-capabilities.sh), [ADR 0002](0002-build-mxe-on-hosted-runners-and-cache-in-ghcr.md), [ADR 0008](0008-images-build-on-self-hosted-runners-and-publish-from-main.md)

## Context

Claude Code sessions for this repo run on the shared Windows host, inside WSL, on other people's Windows, Linux and macOS machines, and in cloud sandboxes. The shared host has a Windows engine, used by the windows-nano-demos runners, and a WSL distro (Ubuntu) with its own Docker Engine, which also runs the user's devcontainers. Switching Docker Desktop to Linux containers would take the runners offline, but the WSL distro's own Docker is a separate engine, so using it doesn't affect them. Until now CLAUDE.md said Linux work never needs a local engine. That made every shellcheck run or `build-libarchive.sh` experiment a CI round trip, even on a host that can run them.

## Decision

Before container work, a session reads a probed report of the host's engines, and routes each task by it.

- **Probe:** `scripts/Get-HostCapabilities.ps1` on Windows, and `scripts/host-capabilities.sh` on Linux, macOS and WSL. Each delegates to the other on the wrong platform. Both write the same JSON (schema version 1) to a gitignored `.claude/host-capabilities.<platform>.local.json`, which is reused for 24 hours. It's probed again on `-Refresh`, after an engine error, or when the overrides file changes. On Windows the probe boots WSL distros so the answer is accurate. It never installs, starts or switches anything.
- **Linux engine order on Windows:** the default WSL distro's Docker, then other WSL 2 distros, then the default docker context if it's Linux, then an existing Docker Desktop Linux engine pipe.
- **Windows engine:** the isolation each LTSC version needs on this host build. Process isolation is used only when the builds match, otherwise Hyper-V, or nothing without a hypervisor.
- **Overrides:** a flat, gitignored `.claude/host-capabilities.overrides.local.json` with `linuxEngine`, `sharedHost` and `maxAgeHours`.
- **Every host counts as shared** unless overridden. Claude's containers and images carry a `claude-` name prefix and the `com.zippy1981.created-by=claude-code` label. On a Linux engine, `Remove-DockerArtifacts.ps1 -Engine Linux` removes only what has both.
- **Fallbacks:** dispatch the matching workflow after asking, or offer to install or start Docker in a WSL distro, after asking. Docker Desktop is never switched.
- **Unchanged:** releases, the MXE image and the published Windows images still come only from CI (ADR 0002, ADR 0008). A local engine is for iterating.

## Consequences

- Local linting and `build-libarchive.sh` experiments work wherever an engine exists, and sessions without one get a clear reason and a fallback.
- Two probe scripts must stay in step: same schema, same field names. The sh probe fills in less (no per-LTSC isolation, no WSL list).
- The shared Linux engine holds the user's devcontainers, so the label is the safety line. Anything Claude creates without it can't be cleaned by the script.
- `*.sh` is now checked out with LF line endings, so the scripts run from a Windows checkout inside Linux containers.

## Alternatives considered

- **A SessionStart hook that probes every session:** every session would pay for it, including sessions that never touch containers. It also boots WSL.
- **Committed per-host profiles:** reviewable, but they put hostnames in a public repo and go stale.
- **A separate dockerd or a dedicated WSL distro for Claude:** stronger isolation from the devcontainers, but a host change and twice the disk use. Labels were enough.
- **Allowing Docker Desktop's Linux mode on hosts not marked shared:** rejected. A mistaken `sharedHost: false` would take the runners offline.
- **One cross-platform PowerShell 7 script:** pwsh isn't on most cloud sandboxes or Macs.
