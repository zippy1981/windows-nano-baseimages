# 0007. curl is the Windows curl with Schannel

- Status: Accepted
- Date: 2026-11-06
- Deciders: zippy1981
- Related: [#5](https://github.com/zippy1981/windows-nano-baseimages/issues/5), [#6](https://github.com/zippy1981/windows-nano-baseimages/issues/6), [0006](0006-tools-take-precedence-over-system32-through-the-machine-path.md)

## Context

Issue #5 planned to replace `C:\Windows\System32\curl.exe` with the official build from <https://curl.se/windows/>. When it was tested on Nano Server ltsc2025, `curl-8.23.0_8-win64-mingw.zip` turned out to:

- use LibreSSL as its only TLS backend;
- no longer ship `curl-ca-bundle.crt`;
- fail every HTTPS request, even with `--ca-native`: `curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)`.

Nano Server's root certificate store starts nearly empty. Schannel downloads missing roots on demand through Windows' root update, but OpenSSL-style backends only read what is already in the store.

## Decision

We will not ship curl.se's curl. `curl` in the image is Windows' own `C:\Windows\System32\curl.exe`, which uses Schannel and the Windows certificate store. `trurl` and `wcurl`, which come in the same zip, aren't shipped either.

The smoke test checks that `curl` resolves to `C:\Windows\System32\curl.exe`, that `curl -V` reports Schannel, and that an HTTPS download works, on every LTSC version.

## Consequences

- HTTPS works out of the box, and custom CA trust (#6) works by adding certificates to the Windows store, the same as for every other Windows program.
- curl's version is Microsoft's and changes with the base image: older on ltsc2019 and ltsc2022, and without HTTP/3. The image no longer pins a curl version.
- The curl rows in #5's design notes (pinning curl.se's build, `where curl` listing the new curl) no longer apply.

## Alternatives considered

- **Ship curl.se's curl with Mozilla's `cacert.pem`:** pinned and bumped by the watcher. HTTPS would work, but certificates would be trusted from a bundle, not the Windows store, so #6 would have to manage two trust stores.
- **Ship curl.se's curl as is:** HTTPS would be broken, which makes curl nearly useless for downloads.
- **Ship curl.se's curl off `PATH`:** rejected as extra weight with no clear user.
