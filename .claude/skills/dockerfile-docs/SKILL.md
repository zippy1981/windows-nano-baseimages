---
name: dockerfile-docs
description: How every Windows Dockerfile in this repo documents itself - a header that says what the image is, how to build it and how its licences are met, and a comment above each build argument that says what it does and how to set it. Use when writing or changing a Dockerfile, adding an ARG, or reviewing Dockerfile comments.
---

# Dockerfile documentation

Each Dockerfile explains itself, so nobody needs the README to build it.

## The header

The file starts with a comment block, before the first `ARG`:

```dockerfile
# windows-nano-base: Nano Server with tar (libarchive 3.8.1), curl, jq, Microsoft Edit and PowerShell 7.
#
# Licensing: each tool's licence is in C:\Program Files\<tool>. (Name any copyleft tool and where its source is.)
#
# Build from this folder (build.cmd does the same):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-base:2022 .
# Each build argument is described where it is declared below.
```

- **First line:** `# <image name>: <what the image is>`, in one sentence that a person choosing an image would understand, at most 100 characters after the colon. Docker Hub uses it as the short description.
- **Licensing:** say where the licences are. For copyleft tools, say where in the image their source or release tarball is.
- **Build example:** a `docker build` line with at least one `--build-arg`, and `--memory 4g`.
- **No `key=value` on the first line.** Docker would read `# key=value` there as a parser directive.

## Build arguments

Put a comment directly above the first `ARG` of each name, with no blank line between them. It says what the argument is, its default if that isn't obvious, and how to set it:

```dockerfile
# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to Nano Server for WINDOWS_VERSION.
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64
```

- A repeated `ARG NAME` in a later stage only brings the value into that stage, so it needs no comment.
- Tool versions and hashes pinned with `ENV` aren't build arguments. Give each tool's `ENV` block a one-line comment naming the tool and its download page.

## Who writes it

`container-author` and `windows-deps-updater` draft these comments. `markdown-reviewer` checks the wording and the format, and `markdown-fixer` applies the changes. It edits `#` lines only, never instructions.
