# Nano Server base image

## Goal

`zippy1981/nanoserver-base:ltsc2019|ltsc2022|ltsc2025`, plus `-pwsh` variants, build and pass their smoke tests in CI on all three versions, with every tool pinned and its licence shipped, and are published from `main` ([zippy1981/windows-nano-baseimages#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5)).

## Context

- `static-3.8.11` (this repo's release) has `libarchive-3.8.11-windows-x64-static-tools.zip`: bsdtar, bsdcpio, bsdcat and bsdunzip, plus licences and the libiconv source.
- The two self-hosted runners `DEARING-HP-Z-base1` and `DEARING-HP-Z-base2` (`self-hosted, windows, nanoserver, docker`) use the shared host's Docker engine, with Hyper-V isolation.
- `main` is protected: squash pull requests only, and the `markdownlint` check is required.

## Decisions

Recorded in #5's comments and in the ADRs.

- The tools go in `C:\tools\bin`, first on the machine `PATH`, and the System32 files are left alone ([ADR 0006](../docs/adr/0006-tools-take-precedence-over-system32-through-the-machine-path.md)).
- curl is System32's (Schannel). curl.se's LibreSSL build can't verify HTTPS on Nano Server ([ADR 0007](../docs/adr/0007-curl-is-the-windows-curl-with-schannel.md)).
- The images build on the self-hosted runners, with bases pinned by the digest pulled. They publish from `main` with ltsc tags ([ADR 0008](../docs/adr/0008-images-build-on-self-hosted-runners-and-publish-from-main.md)).
- PowerShell 7 is a second image `FROM` the base, tagged `-pwsh`.
- Known libarchive gaps are strict expected failures in `tests/archives.json`: Deflate64 (#7), and zips read from a pipe (#8).
- A daily watcher opens bump pull requests and starts their checks with `workflow_dispatch`, because pull requests opened with `GITHUB_TOKEN` start no workflows.

## Plan

### Phase 1: Image and tests

- [x] **container-author**: `images/nanoserver-base/Dockerfile` and `images/nanoserver-base-pwsh/Dockerfile`. Accept: they build for 2019, 2022 and 2025 with `build.cmd <ver>`.
- [x] **powershell-author**: `Save-VerifiedFile.ps1`, `tests/ArchiveTest.psm1`, and both `smoke-test.ps1`. Accept: PSScriptAnalyzer is clean at Warning.
- [ ] **windows-container-tester**: run both smoke tests on 2019, 2022 and 2025. Accept: all pass, with only the recorded expected failures.

### Phase 2: CI, publishing and bumps

- [x] **workflow-author**: `.github/workflows/nanoserver-base.yml`, and `watch-tool-versions.yml`. Accept: the actionlint job in `lint-scripts.yml` is green.
- [ ] **ci-watcher**: the `nanoserver-base` run on the pull request is green on all three versions. Accept: three green legs.
- [ ] **windows-image-publisher**: the first publish from `main`. Accept: all six moving tags exist on Docker Hub. Needs the owner to create the `Docker Hub zippy1981` environment and its secrets first.
- [ ] **release-engineer**: run the watcher with `dry-run`. Accept: it reports every tool current.

### Phase 3: Follow-ups

- [ ] **issue-implementer**: #7 (Deflate64) and #8 (zip from a pipe) in the libarchive build.
- [ ] **planning**: an issue in windows-nano-demos to move onto this base. The 7-Zip workaround for row 1 (LZMA 7z) can go. Rows 2–5 must keep their workarounds until #7 and #8 are fixed.

## Risks

- **The shared host's disk and memory:** each leg extracts about 3 GB in the container. Mitigation: each extraction is deleted after its mtree is written, and builds use `--memory 4g`.
- **curl.se was removed, so curl isn't pinned:** System32 curl changes with the base image. Mitigation: the smoke test checks Schannel and HTTPS on every version.
- **Upstream download URLs move:** curl.se no longer matters. Test archives such as PHP's move to `archives/`. Mitigation: they're cached on each runner, and a move only breaks the first download.
- **Bump pull requests need "Allow GitHub Actions to create pull requests"** in the repo settings. Mitigation: the watcher fails visibly if the setting is off.

## Owners

| Agent | Tasks |
| --- | --- |
| container-author | Dockerfiles, `build.cmd` |
| powershell-author | Build helper, test module, smoke tests, publish and watcher scripts |
| workflow-author | The two workflows |
| windows-container-tester | Smoke tests on all three versions |
| windows-image-publisher | The first Docker Hub publish |
| adr | ADRs 0006–0008 |
