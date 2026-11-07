# 0002. Tools take precedence over System32 through the machine PATH

- Status: Accepted
- Date: 2026-11-06
- Deciders: @zippy1981
- Related: [#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5), [images/nanoserver-base/Dockerfile](../../images/nanoserver-base/Dockerfile), [0003](0003-curl-is-the-windows-curl-with-schannel.md)

## Context

Nano Server ships `C:\Windows\System32\tar.exe`, an old bsdtar that can't read LZMA 7z and silently writes zero-byte files or skips entries for some zips (the table in #5). The base image has to make `tar` mean this repo's libarchive bsdtar, on ltsc2019, ltsc2022 and ltsc2025.

There are two ways to do that. One is to put the new tools in a folder that comes before `System32` on `PATH`. The other is to overwrite the System32 files. Those are owned by TrustedInstaller, and servicing or a rebuilt base layer can bring them back.

Nano Server has no `where.exe`, so a check of what `tar` resolves to has to use cmd's own PATH search (`for %i in (tar.exe) do @echo %~$PATH:i`).

## Decision

We will install the tools to `C:\tools\bin` and put that folder first on the **machine** `PATH`, with `setx /M`, as `ContainerAdministrator`. The value is read from `HKLM\...\Session Manager\Environment` with `reg query`, not from `%PATH%`, so no user `PATH` is copied into the machine value, and `%SystemRoot%` stays an expandable reference. The result on ltsc2025 is `C:\tools\bin;C:\Windows\system32;C:\Windows;`.

Licences and copyleft sources go in `C:\tools\licenses\<tool>`. The folder has no spaces, which avoids the ltsc2019 problem where an unquoted `SHELL` path splits at a space.

We will not use `ENV PATH`. A Docker `ENV PATH` overrides the registry for every process in the container, so a downstream image that runs `setx PATH` (as the windows-nano-demos images do) would see its entries ignored.

## Consequences

- `tar` finds `C:\tools\bin\tar.exe`. The System32 files stay as Microsoft ships them, so servicing can't undo the change.
- A caller that uses the full path `C:\Windows\System32\tar.exe` still gets the old tar. Downstream Dockerfiles must call plain `tar`.
- Downstream images can add their own tools with `setx PATH` (the user `PATH`), which Windows appends after the machine `PATH`. To come before `C:\tools\bin`, they must change the machine `PATH` the same way this image does.
- The smoke test checks `PATH` and the resolved `tar.exe` on all three versions.

## Alternatives considered

- **Overwrite `C:\Windows\System32\tar.exe`:** every caller gets the new tar, even with a full path. But it changes TrustedInstaller-owned OS files, a base-image refresh can restore them, and it hides which tar is running.
- **Both:** combines the drawbacks, for little gain.
- **`ENV PATH` in the Dockerfile:** simpler to read, but it breaks downstream `setx PATH`, as described above.
