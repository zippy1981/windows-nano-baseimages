# Building libarchive for Windows

This repo cross-compiles [libarchive](https://github.com/libarchive/libarchive) for 64-bit Windows on Linux with [MXE](https://mxe.cc), and publishes the results as GitHub releases. The Nano Server images take `bsdtar` from these releases. The decisions behind it are in [docs/adr](adr/README.md); the plan is [plans/issue-1-libarchive-build.md](../plans/issue-1-libarchive-build.md).

## Architecture

```text
watch-upstream.yml (daily) ──► scripts/trigger-latest-release.sh
        │  latest libarchive release missing here?
        ▼
mxe-image.yml (weekly, on mxe/ changes to main, or by hand)
  └─ build mxe/Dockerfile ──► ghcr.io/<owner>/mxe-libarchive:sha-<commit>  (+ :latest from main)

build-libarchive.yml (workflow_dispatch, version X.Y.Z [, mxe_image_commit])
  ├─ version     validate X.Y.Z, pick :latest or :sha-<mxe_image_commit>
  ├─ build       docker pull <image>; docker run <image> scripts/build-libarchive.sh X.Y.Z out   (ubuntu-latest)
  ├─ smoke-test  scripts/Test-LibarchivePackage.ps1 on windows-2022 and windows-2025, and in Nano Server
  └─ release     vX.Y.Z and static-X.Y.Z (default branch only)
```

Everything Linux runs on GitHub-hosted `ubuntu-latest` runners. Nothing runs on the shared Windows host.

| File | What it does |
| --- | --- |
| `mxe/Dockerfile` | Ubuntu 24.04 (pinned by digest) with MXE pinned to a commit, building both targets and the dependencies. Runs as the non-root user `mxe` (uid 1001). |
| `mxe/record-mxe-info.sh` | Writes `/opt/mxe/mxe-info.json` (MXE commit and package versions), and copies licences to `/opt/mxe/licenses` and the libiconv source to `/opt/mxe/sources`. |
| `scripts/mxe-image-tag.sh` | Prints the image reference: `ghcr.io/<owner>/mxe-libarchive:latest`, or `:sha-<full SHA>` for a commit given as its argument. |
| `scripts/build-libarchive.sh` | Downloads, verifies, configures, builds, validates and packages one release. |
| `scripts/Test-LibarchivePackage.ps1` | The Windows smoke test of one package. |
| `scripts/trigger-latest-release.sh` | The upstream check and dispatch. |
| `keys/libarchive-release-keys.asc` | The OpenPGP keys libarchive releases are signed with. |
| `.github/workflows/mxe-image.yml` | Builds the MXE image and pushes it to GHCR: weekly, when `mxe/` changes on `main`, and by hand. |
| `.github/workflows/build-libarchive.yml` | The build, test and release workflow. |
| `.github/workflows/watch-upstream.yml` | The daily upstream watcher. |
| `.github/workflows/lint-scripts.yml` | actionlint, shellcheck and PSScriptAnalyzer. |

## MXE targets and dependencies

The image builds MXE's `x86_64-w64-mingw32.static` and `x86_64-w64-mingw32.shared` targets with the packages `cc zlib bzip2 xz lz4 zstd openssl expat libxml2 libiconv pcre2`. At MXE `a6738d9d` those are GCC 15.3.0, zlib 1.3.2, bzip2 1.0.8, xz 5.8.4, lz4 1.10.0, zstd 1.5.7, OpenSSL 4.1.0, Expat 2.9.0, libxml2 2.15.4, libiconv 1.19 and PCRE2 10.49. Each build's manifest records the versions it used.

### Feature matrix

| Feature | How | State |
| --- | --- | --- |
| tar, pax, cpio, zip, 7-Zip, RAR and RAR5 (read), ISO9660, XAR, WARC, CAB, LHA, ar, mtree, shar, raw | Built into libarchive | On |
| gzip / deflate | zlib, `ENABLE_ZLIB` | On, required |
| bzip2 | `ENABLE_BZip2` | On, required |
| xz / LZMA | `ENABLE_LZMA` | On, required |
| LZ4 | `ENABLE_LZ4` | On, required |
| Zstandard | `ENABLE_ZSTD` | On, required |
| Encryption and digests | OpenSSL (`ENABLE_OPENSSL`) and Windows CNG (`ENABLE_CNG`) | On, required |
| XAR's XML | libxml2 (`ENABLE_LIBXML2`), which needs iconv | On, required |
| Character sets | libiconv (`ENABLE_ICONV`) | On, required |
| `bsdtar -s` regex | PCRE2 POSIX (`ENABLE_PCRE2POSIX`) | On, required |
| BLAKE2 | libb2 (`ENABLE_LIBB2`) | Not in MXE; libarchive's bundled copy is used |
| LZO | `ENABLE_LZO` | Off: GPL-2.0 |
| mbedTLS, Nettle | `ENABLE_MBEDTLS`, `ENABLE_NETTLE` | Off: OpenSSL and CNG cover them |
| Expat, bsdxml | `ENABLE_EXPAT`, `ENABLE_BSDXML` | Off: libxml2 is used |
| ACLs, extended attributes | `ENABLE_ACL`, `ENABLE_XATTR` | Off: POSIX only |

"Required" means `build-libarchive.sh` fails if the matching `config.h` define (for example `HAVE_ZSTD_H` and `HAVE_LIBZSTD`) is not set after configuring. Every release gets the same fixed set of CMake options, written out in the script: libarchive has kept its `ENABLE_*` options stable across releases, and if a release drops or renames one, its configure or feature check fails and the script is changed.

## Release artifacts

For libarchive `X.Y.Z`:

| Release | Asset | Contents |
| --- | --- | --- |
| `vX.Y.Z` | `libarchive-X.Y.Z-windows-x64-static.zip` | `bin/` static `bsdtar`, `bsdcpio`, `bsdcat`, `bsdunzip`; `lib/libarchive.a` and the dependencies' static libraries; `include/`; `lib/pkgconfig`; man pages; licences; manifest |
| `vX.Y.Z` | `libarchive-X.Y.Z-windows-x64-shared.zip` | `bin/` the tools, `libarchive.dll` and every non-system DLL they need; `lib/libarchive.dll.a`; `include/`; licences; manifest |
| `static-X.Y.Z` | `libarchive-X.Y.Z-windows-x64-static-tools.zip` | The static tools, `licenses/`, `sources/` and the manifest only |

Every zip has one top-level folder named after the zip, with:

- `manifest.json` and `MANIFEST.txt`: the libarchive version, source URL, SHA-256 and signing key, target, linkage, the features found and not found, the crypto back ends, each tool's DLL imports, the dependency versions, the MXE commit, GCC and CMake versions, the build date and the CMake command line.
- `licenses/`: libarchive's `COPYING` and the licence files of every library linked in, plus the GCC runtime and mingw-w64.
- `sources/`: the libiconv release tarball, because libiconv is LGPL-2.1.

## Running a build

### From GitHub Actions

The workflows must be on the default branch before they can be dispatched or scheduled.

```bash
gh workflow run build-libarchive.yml --repo zippy1981/windows-nano-baseimages -f version=3.8.11
```

```bash
gh run watch --repo zippy1981/windows-nano-baseimages
```

```bash
gh release view v3.8.11 --repo zippy1981/windows-nano-baseimages
```

The build never builds MXE. It pulls `:latest`, so run `mxe-image.yml` on `main` once (about an hour) before the first build, and again after any change you don't want to wait a week for. A dispatch from another branch builds and tests, but doesn't publish. A push that touches the build or test scripts, `keys/` or `build-libarchive.yml` runs a test build of `TEST_VERSION` (set in `build-libarchive.yml`). The release notes and the run summary record the image digest and the commit it was built from.

To build with a particular image instead of `:latest`, pass the commit of this repo that the image was built from. Every `mxe-image.yml` run tags its image `sha-<commit>`, including runs on other branches, so this is also how to try a Dockerfile change before it merges:

```bash
gh workflow run mxe-image.yml --repo zippy1981/windows-nano-baseimages --ref my-branch
gh workflow run build-libarchive.yml --repo zippy1981/windows-nano-baseimages --ref my-branch -f version=3.8.11 -f mxe_image_commit=<commit>
```

### Locally, on Linux

Build the image (about an hour), or pull the published one (`:latest`, or `scripts/mxe-image-tag.sh <commit>` for a pinned one):

```bash
docker build --tag mxe-libarchive:local mxe
```

```bash
docker pull "$(scripts/mxe-image-tag.sh)"
```

Then mount the repo at `/work`, the image's working directory, and build a release into `./out`. The command depends on the container engine, because the image runs as the user `mxe` (uid 1001) and the files the build writes must end up owned by you.

With **rootless podman** (Fedora's default, and what `docker` is when `podman-docker` is installed):

```bash
podman run --rm --userns=keep-id:uid=1001,gid=1001 --volume "$PWD:/work:z" mxe-libarchive:local scripts/build-libarchive.sh 3.8.11 out
```

With **Docker** (rootful, the usual install):

```bash
docker run --rm --user "$(id -u):$(id -g)" --volume "$PWD:/work:z" mxe-libarchive:local scripts/build-libarchive.sh 3.8.11 out
```

For a shell in the container instead, drop the script and add `-it` (for example `podman run --rm -it --userns=keep-id:uid=1001,gid=1001 --volume "$PWD:/work:z" mxe-libarchive:local`). Use the published image's name (`ghcr.io/zippy1981/mxe-libarchive:latest`) in place of `mxe-libarchive:local` if you pulled it.

Why each part is there:

- **`:z`** relabels the repo `container_file_t` so SELinux lets containers read it. Without it, on an SELinux host such as Fedora, `ls /work` gives `Permission denied` even though the uids match. Use `:z` (shared), not `:Z`: `:Z` gives the directory a label private to one container, and every later container without `:Z` is then refused. On hosts without SELinux, and on GitHub's runners, Docker ignores it.
- **`--userns=keep-id:uid=1001,gid=1001`** maps your uid to `mxe` inside the container. Rootless podman runs containers in a user namespace where container root is you and every other uid is one of your subordinate uids, so `--user "$(id -u):$(id -g)"` (the workflow's form) runs as a stranger: your files show up owned by `root`, and the build can't write `out/`.
- **`--user "$(id -u):$(id -g)"`** does the same job on rootful Docker, where uids inside and outside the container are the same. The workflow uses it because the runner's uid is 1001 too. Rootless Docker behaves like rootless podman here: run it without `--user`, as container root, which is you.

`build-libarchive.sh --help` lists its options. It always builds the signed tarball from the GitHub release `vX.Y.Z`.

### Testing a package on Windows

```powershell
./scripts/Test-LibarchivePackage.ps1 -PackagePath out/libarchive-3.8.11-windows-x64-static-tools.zip -ExpectedVersion 3.8.11 -NanoServerImage mcr.microsoft.com/windows/nanoserver:ltsc2025
```

## Automated release detection

`watch-upstream.yml` runs daily at 05:23 UTC, and by hand (with a dry-run option). `scripts/trigger-latest-release.sh`:

1. Reads `GET /repos/libarchive/libarchive/releases/latest`, which never returns drafts or prereleases, and takes `X.Y.Z` from the `vX.Y.Z` tag.
2. Checks this repo for the releases `vX.Y.Z` and `static-X.Y.Z`. If both exist, it logs "Up to date" and stops.
3. Otherwise, if no `Build libarchive X.Y.Z` run is queued or running, it dispatches `build-libarchive.yml` on the default branch with `version=X.Y.Z`.

It retries network errors and 5xx responses, waits out rate limits (`429`, or `403` with `x-ratelimit-remaining: 0`) for up to 5 minutes, and exits non-zero on anything else. Run it yourself with:

```bash
GH_TOKEN=$(gh auth token) scripts/trigger-latest-release.sh --dry-run
```

## Permissions and settings

Each workflow sets `permissions: {}` and grants each job only what it needs:

| Job | Permissions |
| --- | --- |
| `mxe-image.yml` `image` | `contents: read`, `packages: write` (push to GHCR) |
| `build-libarchive.yml` `version` | `contents: read` |
| `build-libarchive.yml` `build` | `contents: read`, `packages: read` |
| `build-libarchive.yml` `smoke-test` | `contents: read` |
| `build-libarchive.yml` `release` | `contents: write` (create releases and tags) |
| `watch-upstream.yml` `check` | `contents: read`, `actions: write` (dispatch a workflow) |

No secrets beyond the automatic `GITHUB_TOKEN` are needed. A dispatch made with `GITHUB_TOKEN` does start the build workflow. Repository settings:

- **Actions, General, Workflow permissions:** either setting works, because every job declares its permissions.
- **Packages:** the first push creates the private package `mxe-libarchive` linked to this repo. Make it public, or grant other repos access, only if they need the image.
- **Scheduled workflows** stop after 60 days without repository activity. Re-enable `watch-upstream.yml` and `mxe-image.yml` in the Actions tab if that happens.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `build` can't pull the MXE image | No `mxe-image.yml` run has pushed that tag yet. Run it on `main` for `:latest`, or on the commit you passed as `mxe_image_commit`. |
| `mxe-image.yml` hits its 350-minute timeout | MXE grew. Split `mxe/Dockerfile` into a toolchain stage and a packages stage, each pushed as its own tag. |
| An MXE package fails to download | Its upstream moved. Bump `MXE_COMMIT` to a commit with the fix; the `mxe-build-log` artifact has the log. |
| `features not found by CMake: HAVE_...` | A dependency failed to link in a CMake check. Read `configure-<variant>.log` in the `libarchive-X.Y.Z-logs` artifact. |
| `imports X.dll, which is not a Windows system DLL` | A static tool linked a DLL. Check the static libraries in MXE, or the `system_dll_re` allowlist if the DLL is a genuine Windows one. |
| `signature check failed` | A release was signed with a new key. Confirm it on libarchive's release page, then add it to `keys/libarchive-release-keys.asc`. |
| The smoke test's Nano Server check is skipped | The runner image has no Docker, or the pull failed. The tool tests on the host still ran. |
| The watcher says the workflow is not on the default branch | Merge the workflows to `main` first. |
| `Permission denied` on `/work` in a local container | SELinux or rootless uid mapping. Mount with `:z`, and with rootless podman use `--userns=keep-id:uid=1001,gid=1001` instead of `--user` (see "Locally, on Linux"). |

## Security

- Release tarballs are verified with `gpgv` against the committed keyring, and the tarball must contain only `libarchive-X.Y.Z/` with a matching `archive.h` version.
- The Ubuntu base is pinned by digest and MXE by commit. MXE checks each package download against the SHA-256 in its recipe.
- The image runs as a non-root user and holds no credentials. The GHCR login uses `GITHUB_TOKEN` and is logged out after the pull.
- The version input is validated as `X.Y.Z` before use, and reaches shell steps only through `env:`.
- Checkouts don't persist credentials, and only the `release` job can write to the repo.

## Known limitations

- **The self-hosted runner and `Run-MxeRunner.ps1` from issue #1 are not implemented.** Builds use hosted runners instead (ADR 0002); add them only if a persistent runner is wanted.
- **ltsc2019 isn't tested here.** Hosted runners have no Server 2019 image. The tools import only system DLLs and `msvcrt.dll`, which ltsc2019 has; the Nano Server images test them on ltsc2019.
- **libarchive's own test suite doesn't run**, because it needs Windows. The smoke tests cover each format and filter instead.
- **`bsdtar --version` doesn't list OpenSSL.** It lists zlib, liblzma, bz2lib, liblz4, libzstd, libxml2 and cng; the manifest's `config.h` features record OpenSSL. libarchive uses Windows CNG for its digests and zip encryption, and OpenSSL where CNG has no implementation.
- **Only the latest upstream release is watched.** Older versions can be dispatched by hand. They get the same CMake options and must build the same four tools, so a release that lacks an option or `bsdunzip` fails the build.
