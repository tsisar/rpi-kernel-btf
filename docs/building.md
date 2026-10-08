# Building

The build is four scripts, run in order, inside a Debian trixie **arm64**
environment. GitHub Actions does exactly this (`.github/workflows/build.yml`);
the same steps work locally in a container.

| Script | Does | Needs |
|---|---|---|
| `scripts/fetch.sh` | Downloads `.dsc`, `orig.tar.xz`, `debian.tar.xz` for the version in `VERSION` into `build/`, verifies sha256 against the `.dsc` | `curl` |
| `scripts/prepare.sh` | `dpkg-source -x`; appends `config/<flavour>.btf` to `debian/config/arm64/rpi/config.<flavour>`; rewrites the top changelog stanza's version to `+btf`; regenerates `debian/control` / `rules.gen`; writes `build/out/metadata.json` | `dpkg-dev`, `python3-dacite`, `python3-jinja2`, `kernel-wedge`, `quilt` (the `.dsc` Build-Depends) |
| `scripts/build.sh` | Installs build-deps + `dwarves`; `source` → `build-arch_arm64_rpi_<flavour>_{base,headers,image,meta}` → `binary-arch_…` + `binary-indep_rpi_headers-common`; collects `*.deb`, `SHA256SUMS`, `buildinfo.txt` | root, arm64; 1 h 54 min on the 4-core hosted runner |
| `scripts/verify.sh` | `.BTF` section in the build-tree `vmlinux` (parsed by `bpftool`), raw BTF magic `9f eb 01 00` in the shipped `Image`, `.BTF` in a module, `CONFIG_DEBUG_INFO_BTF=y` in the shipped config, package name/version as planned | `bpftool`, `binutils` |

Inputs: `VERSION` (the Pi OS source version) and `SUFFIX` (the local suffix,
`+btfN`; bump it when the fragment changes for the same Pi OS version).
Settings (environment): `FLAVOUR` (default `2712`), `BTF_SUFFIX` (overrides
`SUFFIX`), `BUILD_DIR` (default `./build`), `JOBS` (default `nproc`),
`SKIP_DEPS=1` to skip the apt steps in `build.sh`.

## Locally

```sh
docker run --rm -it --platform linux/arm64 -v "$PWD":/w -w /w debian:trixie bash
apt-get update && apt-get install -y --no-install-recommends curl ca-certificates dpkg-dev
scripts/fetch.sh
apt-get build-dep -y ./build/linux_*.dsc      # or let build.sh do it
scripts/prepare.sh
scripts/build.sh
scripts/verify.sh
```

`build/` is git-ignored. A build needs about 12 GB free: the source tree with
compressed DWARF objects is 11 GB, the packages together are under 60 MB.
On macOS, keep `BUILD_DIR` on a Docker volume (`-v rpi-kernel-build:/build
-e BUILD_DIR=/build`): the Linux tree has paths that differ only by case,
which a bind-mounted case-insensitive filesystem cannot extract.

## What is and is not built

Only flavour `2712` (Pi 5, 16K pages) and only its `base`, `headers`,
`image` and `meta` packages plus the arch-independent
`linux-headers-<abi>-common-rpi`. The `-dbg` package (full-DWARF `vmlinux`,
~1 GB), the `v8`/`v8-rt` flavours, tools and docs are skipped — see
`docs/adr/0002-build-only-what-the-nodes-install.md`.

## Releasing

Tag the commit `v<VERSION><SUFFIX>`, e.g. `v6.18.50-1+rpt1+btf2`; the
workflow attaches the packages, `SHA256SUMS`, `metadata.json`, `buildinfo.txt`
and the resolved kernel config to the GitHub Release. A new Pi OS upload is
followed by bumping `VERSION` (and resetting `SUFFIX` to `+btf1`) and tagging
again; a rebuild of the same version bumps `SUFFIX`.
