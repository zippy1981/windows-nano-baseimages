# Claude Code agents

This folder holds the [Claude Code subagents](https://docs.claude.com/en/docs/claude-code/sub-agents) for this repo. Each file's YAML front matter sets the agent's `name`, `description`, `tools` and `model`, and the body is its system prompt. `CLAUDE.md` at the repo root has the context they share. Most came from windows-nano-demos and were adapted to this repo. The issue agents are new.

## Agents

| Agent | Purpose | Model | Tools |
| --- | --- | --- | --- |
| `issue-implementer` | Takes one issue end to end: plan, delegate each phase, verify, and report against the issue's checklist. | opus | Read, Glob, Grep, Bash, Agent |
| `mxe-builder` | The Linux MXE cross-compile image (static and shared x86_64 targets, libarchive's dependencies), built on GitHub-hosted runners and cached in GHCR. | sonnet | Read, Glob, Grep, Write, Edit, Bash, WebFetch |
| `libarchive-builder` | `scripts/build-libarchive.sh`: a verified source download, the feature matrix, static and shared builds, PE validation, the three zips and the manifest. | sonnet | Read, Glob, Grep, Write, Edit, Bash, WebFetch |
| `release-engineer` | `build-libarchive.yml`, `watch-upstream.yml` and `scripts/trigger-latest-release.sh`: idempotent `vX.Y.Z` and `static-X.Y.Z` releases. | sonnet | Read, Glob, Grep, Write, Edit, Bash |
| `cicd-engineer` | CI/CD design: hosted Linux builds, caching, releases, how the Windows images are built for 2019, 2022 and 2025, and permissions. | opus | Read, Glob, Grep, Write, Edit, Bash, PowerShell, WebFetch |
| `workflow-author` | Workflow YAML to `cicd-engineer`'s design, checked with actionlint. | sonnet | Read, Glob, Grep, Write, Edit, Bash |
| `container-author` | The Windows Nano Server Dockerfiles and `build.cmd`: tar, curl, jq, yq, edit, pwsh and future tools. Hands Dockerfile documentation to `markdown-reviewer`. | sonnet | Read, Glob, Grep, Write, Edit, WebFetch, Agent |
| `windows-dockerfile-reviewer` | Read-only review of the Windows Dockerfiles for Nano Server pitfalls, licences and size. | opus | Read, Glob, Grep |
| `windows-container-builder` | Builds the Windows images on the Windows engine, one version at a time. | sonnet | PowerShell, Read, Glob, Grep |
| `windows-container-tester` | Smoke-tests every tool in the images on 2019, 2022 and 2025. | sonnet | PowerShell, Read, Glob, Grep |
| `windows-deps-updater` | Bumps the pinned versions and SHA-256 hashes: libarchive, MXE, curl, jq, Edit, PowerShell, 7-Zip and the base tags. | sonnet | Read, Edit, Glob, Grep, Bash, WebFetch, Agent |
| `windows-image-publisher` | Pushes tested images to Docker Hub, only when the user asks. | haiku | PowerShell, Read |
| `windows-host-doctor` | Diagnoses the Windows host: the engine, Hyper-V, disk and power. | haiku | PowerShell, Read, Glob, Grep |
| `powershell-author` | PowerShell 7 scripts (for example `Run-MxeRunner.ps1`), with `[CmdletBinding()]`, help, and a clean PSScriptAnalyzer run. | sonnet | Read, Glob, Grep, Write, Edit, PowerShell |
| `ci-watcher` | Waits for a run or a PR's checks and reports the outcome and the failing lines. | haiku | Bash, Read |
| `planning` | Writes plans in `plans/`, with an owner and an acceptance check per task. Writes only under `plans/`. | haiku | Read, Glob, Grep, Write, Edit, Agent |
| `adr` | MADR-style decision records in `docs/adr/` and their index. Writes only under `docs/adr/`. | sonnet | Read, Glob, Grep, Write, Edit |
| `governance` | Read-only audit of agents, images, builds, releases, workflows and docs, as a ranked gap report. | opus | Read, Glob, Grep |
| `markdown-reviewer` | Read-only Markdown review, and review of Dockerfile documentation comments. Hands fixes to `markdown-fixer`. | haiku | Bash, Read, Glob, Grep, Agent |
| `markdown-fixer` | Fixes markdownlint errors and applies Dockerfile comment fixes. | haiku | Bash, Read, Edit, Glob, Grep |

## Skills

- `markdown-lint`: running markdownlint the way CI does.
- `dockerfile-docs`: the Dockerfile header, licensing note and `ARG` comment format.
- `safe-docker-cleanup`: removing only your own containers and images on the shared host, on either engine (`scripts/Remove-DockerArtifacts.ps1`).
- `host-capabilities`: which engines this host has (Windows, WSL's Linux Docker, or neither), and whether a task runs locally or in GitHub Actions (`scripts/Get-HostCapabilities.ps1`, `scripts/host-capabilities.sh`).

## How models were chosen

- **haiku:** mechanical or read-mostly work with a fixed procedure: watching CI, lint fixes, host checks, a guarded push, and filling in plans.
- **sonnet:** bounded authoring and building, such as Dockerfiles, scripts, workflows and ADRs.
- **opus:** design and deep review, where a miss is expensive: coordinating an issue, CI/CD design, Dockerfile review, and governance.

## Delegation

```text
issue-implementer ──► planning ──► adr
                  ──► cicd-engineer (design) ──► workflow-author
                  ──► mxe-builder ──► libarchive-builder ──► release-engineer
                  ──► powershell-author (Run-MxeRunner.ps1, only if the self-hosted runner is wanted)
                  ──► container-author ──► markdown-reviewer ──► markdown-fixer
                                       ──► windows-dockerfile-reviewer ──► windows-container-builder
                                           ──► windows-container-tester ──► windows-image-publisher (only when asked)
                  ──► ci-watcher (waiting for runs) ──► governance (final audit)
```

Claude Code subagents can't start other subagents, so a hand-off only runs directly when the delegating agent is the main agent. Otherwise the agent's report names the next agent, and the caller starts it.
