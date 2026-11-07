# 0004. Images build on self-hosted runners and publish from main

- Status: Accepted
- Date: 2026-11-06
- Deciders: @zippy1981
- Related: [#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5), [.github/workflows/nanoserver-base.yml](../../.github/workflows/nanoserver-base.yml)

## Context

Every image must build and pass its tests on ltsc2019, ltsc2022 and ltsc2025. GitHub-hosted Windows runners can't run ltsc2019 containers: there's no `windows-2019` runner any more, and hosted runners have no Hyper-V isolation. This repo has two self-hosted runners on the shared Windows host, `DEARING-HP-Z-base1` and `DEARING-HP-Z-base2`, labelled `self-hosted, windows, nanoserver, docker`. They're containers that use the host's Docker engine, which defaults to Hyper-V isolation.

## Decision

We will build and test the Windows images on those two runners, as a matrix over the three LTSC versions, with `docker build --memory 4g`. Pull requests from forks don't run on them, because the runners have access to the host's Docker engine.

Each run pins the Nano Server and Server Core bases by the digest it pulled, and records it in the image's `org.opencontainers.image.base.digest` label.

We will publish to Docker Hub as `zippy1981/nanoserver-base` only from `main`, through the `Docker Hub zippy1981` environment, which holds `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`. Only an image that passed its smoke test in the same job is pushed. Tags:

| Tag | Moves | Image |
| --- | --- | --- |
| `ltsc2019`, `ltsc2022`, `ltsc2025` | Yes | The base image |
| `ltsc<ver>-<os-build>-<sha7>`, for example `ltsc2025-10.0.26100.6899-1a2b3c4` | No | The base image |
| `ltsc<ver>-pwsh` | Yes | The base image plus PowerShell 7 |
| `ltsc<ver>-pwsh-<os-build>-<sha7>` | No | The base image plus PowerShell 7 |

## Consequences

- Builds use the shared host. The runners only remove the images and containers they created (CLAUDE.md, the `safe-docker-cleanup` skill).
- The test archives are cached on each runner under `RUNNER_TOOL_CACHE`, so a runner downloads them once.
- Docker Hub needs an environment and secrets that the repository owner creates. The workflow fails clearly if they're missing.

## Alternatives considered

- **GitHub-hosted `windows-2022` and `windows-2025` runners, with ltsc2019 tested by hand:** breaks the rule that every image is tested on all three versions in CI.
- **Sharing windows-nano-demos' runners through an org runner group:** would change the other repo's setup.
