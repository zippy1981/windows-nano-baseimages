---
name: safe-docker-cleanup
description: Remove leftover Docker containers and images from experiments on this repo's shared host without touching CI, the runners or other sessions' work. Use after any local experiment or spike, or when asked to clean up images.
---

# Safe Docker cleanup

The Docker daemon on this host is shared with the windows-nano-demos repo: its five self-hosted runner containers, every agent, and the user's other sessions. Broad cleanup commands destroy other people's work and the build cache, so **never run `docker system prune`, `docker image prune`, `docker container prune`, `docker builder prune` or `docker rmi` on images you didn't create.**

## While experimenting

Name everything you create with one unique prefix, for example `cgo-exp-`, `mysql-spike` or `<task>-test-`, using `--name` for containers and `-t` for images. That makes cleanup exact.

## Cleaning up

```pwsh
./scripts/Remove-DockerArtifacts.ps1 -Prefix cgo-exp- -WhatIf    # list what would go
./scripts/Remove-DockerArtifacts.ps1 -Prefix cgo-exp-            # remove containers, then untag images
./scripts/Remove-DockerArtifacts.ps1 -Prefix cgo-exp- -IncludeParents   # also free their layers
```

- **Default:** images are untagged with `docker rmi --no-prune`, which keeps their parent layers. Those layers may be the build cache that CI relies on: removing an image *with* its parents is what made CI rebuild from scratch.
- **`-IncludeParents`:** use it only for images built from bases nothing else uses, such as a throwaway experiment.
- **Refusals:** the script refuses prefixes shorter than 4 characters and any prefix that overlaps the runners (`DEARING-HP-Z-nano*`), the runner and cache images, `zippy1981/` or `mcr.microsoft.com`.

## The Linux engine

The host also has a Linux engine: the WSL distro's own Docker, which the `host-capabilities` skill finds. The user's devcontainers run there. On that engine, name everything `claude-<task>-<tag>` and label it `com.zippy1981.created-by=claude-code` (the `host-capabilities` skill). Then clean up with `-Engine Linux`:

```pwsh
./scripts/Remove-DockerArtifacts.ps1 -Prefix claude-lint- -Engine Linux -WhatIf
./scripts/Remove-DockerArtifacts.ps1 -Prefix claude-lint- -Engine Linux
```

With `-Engine Linux`, a container or image is removed only if it has both the prefix and the label. Remove an image you pulled (it has no label) by its exact reference, and only if it wasn't there before you pulled it. Never run `wsl --shutdown` or `wsl --terminate`.

## Things to leave alone

- Containers named `DEARING-HP-Z-nano*` (the runners) and `windows-nano-artifact-cache`
- Base images from `mcr.microsoft.com/windows/*`
- Images another session is building: check `docker ps` for build containers before cleaning
