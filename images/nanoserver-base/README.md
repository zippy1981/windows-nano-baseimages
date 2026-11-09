# nanoserver-base

Nano Server with a modern `tar` (libarchive bsdtar), `jq` and Microsoft Edit, for ltsc2019, ltsc2022 and ltsc2025 ([#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5)). The `-pwsh` tags add PowerShell 7 ([nanoserver-base-pwsh](../nanoserver-base-pwsh/Dockerfile)).

```dockerfile
FROM zippy1981/nanoserver-base:ltsc2025
RUN curl -fsSL -o go.zip https://go.dev/dl/go1.27.3.windows-amd64.zip && tar -xf go.zip -C C:\ && del go.zip
```

## What's in it

| Command | Version | From | Licence |
| --- | --- | --- | --- |
| `tar` (bsdtar), `bsdcpio`, `bsdcat`, `bsdunzip` | libarchive 3.8.11 | This repo's [`static-3.8.11`](https://github.com/zippy1981/windows-nano-baseimages/releases/tag/static-3.8.11) release | BSD-2-Clause. Statically links zlib, xz, bzip2, lz4, zstd, libxml2, OpenSSL and LGPL-2.1 libiconv, whose source tarball is in `C:\tools\licenses\libarchive\sources`. |
| `jq` | 1.8.2 | [jqlang/jq](https://github.com/jqlang/jq/releases) | MIT |
| `edit` | 2.0.0 | [microsoft/edit](https://github.com/microsoft/edit/releases) | MIT |
| `curl` | Windows' own | `C:\Windows\System32\curl.exe`, which uses Schannel and the Windows certificate store ([ADR 0007](../../docs/adr/0007-curl-is-the-windows-curl-with-schannel.md)) | Shipped with Windows |
| `vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll` in `C:\Windows\System32` | 14.51.36247.0 | Microsoft Visual C++ v14 Redistributable (x64), checked as described in [the README](../../README.md#visual-c-runtime-dlls) | Microsoft's redistributable code; see `C:\tools\licenses\vcredist\NOTICE.txt` |
| `pwsh` (`-pwsh` tags only) | 7.6.9 | [PowerShell/PowerShell](https://github.com/PowerShell/PowerShell/releases) | MIT, in `C:\Program Files\PowerShell\7` |

The image adds about 35 MB to Nano Server (300 MB for ltsc2019, 338 MB for ltsc2022, 522 MB for ltsc2025). The `-pwsh` tags add about 260 MB more.

The SHA-256 of every download is pinned in the [Dockerfile](Dockerfile) and checked during the build. A daily workflow opens a bump pull request for a new release.

The tools are in `C:\tools\bin`, which comes first on the machine `PATH`. `C:\Windows\System32\tar.exe` is still there, so call plain `tar`, not its full path ([ADR 0006](../../docs/adr/0006-tools-take-precedence-over-system32-through-the-machine-path.md)). To add your own tools, use `setx PATH` (the user `PATH`, after the machine `PATH`).

## Known limitations

> [!WARNING]
> **Never pipe a zip into `tar`** (`curl ... | tar -xf -`). On Windows, libarchive silently drops about the first 64 KB of a zip read from a pipe, and exits 0 ([#8](https://github.com/zippy1981/windows-nano-baseimages/issues/8)). Download to a file and run `tar -xf file.zip`.

- **Deflate64 zips can't be extracted** ([#7](https://github.com/zippy1981/windows-nano-baseimages/issues/7)). `tar` fails loudly with `Unsupported ZIP compression method (9: deflation-64-bit)`, so you notice, but you still need 7-Zip for these zips, for example GNU nano for Windows.
- **Edit** loads `icu.dll` at run time, which Nano Server doesn't have. Search and word wrap fall back to simpler behaviour.
- Nano Server has no `where.exe` or `whoami.exe`. Use `for %i in (tar.exe) do @echo %~$PATH:i` and `echo %USERNAME%`.

## Tests

`smoke-test.ps1` runs in CI on all three versions, as `ContainerUser`. It checks:

1. `PATH` starts with `C:\tools\bin`, `tar` resolves to `C:\tools\bin\tar.exe` and `curl` to `C:\Windows\System32\curl.exe`.
2. Every tool runs and reports the pinned version. No tool may fail with `0xC0000135` or `0xC0000139`, the missing-DLL and missing-entry-point errors ltsc2019 is prone to.
3. `curl` reports Schannel, and an HTTPS download works.
4. `echo {"a":[1,2]}| jq -c .a` prints `[1,2]`.
5. Each Visual C++ runtime DLL in [redistributables.json](redistributables.json) is in `C:\Windows\System32`, is Microsoft's, and is listed in its `NOTICE.txt`. The `-pwsh` smoke test also loads each one and checks it's the pinned version.
6. [tests/downstream/smoke-test.ps1](../../tests/downstream/smoke-test.ps1) builds a throwaway image `FROM` the base with executables that need the Visual C++ runtime but bring none of their own, and checks that they run.
7. Every archive in [tests/archives.json](../../tests/archives.json) is extracted from a file and from a pipe, and checked file by file: path, size and SHA-256 against the zip's central directory, read with .NET; for the 7z, path and size from its headers. Known failures are strict: the test fails if they stop failing, so the entry gets removed.

Run it locally after `build.cmd`:

```powershell
./images/nanoserver-base/smoke-test.ps1 -Image nanoserver-base:ltsc2025
```
