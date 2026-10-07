# Plan: rebuild the Raspberry Pi OS kernel with BTF

Status: plan, being implemented in this repository (written 2026-09-23 in the
cluster repo, moved here 2026-10-07). Nothing here has been run yet; the numbers
marked "expected" are estimates to be replaced by measurements from the first
build. Target version moved from 6.18.39 to **6.18.50-1+rpt1** (the current Pi OS
upload; it also carries newer `macb` NIC fixes the nodes want).

## Why

Cilium ≥ 1.20 (and every patch release since 2026-09-15) needs BTF *inside the
kernel*: its SNAT helpers are global BPF subprograms whose `ctx` argument the
kernel verifier checks against the kernel's own vmlinux BTF, and its socket
destroyer is a BPF iterator that the kernel resolves the same way. A detached
BTF blob under `/lib/modules` only serves user-space CO-RE relocations — it
got us to 1.19.8, it cannot get us to 1.20 (`cilium/cilium#47718`, canary on
a worker node on 2026-09-21).

Raspberry Pi will not ship BTF (`raspberrypi/linux#6622`). Debian's mainline
arm64 kernel has it, but on the Pi 5 it has no thermal zone and no fan driver:
the SoC temperature is invisible to Linux and the Active Cooler stays off
(a separate research report, R1). That was rejected:
temperature monitoring stays.

The remaining path keeps everything Raspberry Pi OS gives us — thermal zone,
fan, `vcgencmd`, 16K pages, overlays, the `raspi-firmware` hooks, the cluster
repo's serial kernel-upgrade playbook — and changes exactly one thing: the
kernel is built with `CONFIG_DEBUG_INFO_BTF=y`.

## What exactly gets built

**The same source package Raspberry Pi OS builds**, unchanged except for the
BTF options and a version suffix.

- Source: `http://archive.raspberrypi.com/debian/pool/main/l/linux/` publishes
  `linux_<ver>.orig.tar.xz`, `linux_<ver>-1+rpt1.debian.tar.xz` and the `.dsc`
  (verified 2026-09-23 for `6.18.39-1+rpt1` and `6.18.50-1+rpt1`). The
  packaging is Debian's `debian_linux` tooling with a Raspberry Pi featureset:
  `debian/config/arm64/rpi/config` (common, generated from the upstream
  defconfigs by `debian/bin/rpi/genconfigs`) plus per-flavour fragments
  `config.2712`, `config.v8`, `config.v8-rt`; flavours are declared in
  `debian/config/arm64/defines.toml` (`featureset = rpi`, flavours `v8`,
  `v8-rt`, `2712`).
- The 2712 fragment today: `CONFIG_ARM64_16K_PAGES=y`,
  `CONFIG_ARM64_VA_BITS_47=y`, `CONFIG_LOCALVERSION="-v8-16k"`,
  `CONFIG_PREEMPT=y`, a few drivers. No `DEBUG_INFO*` option is set anywhere
  in the Pi packaging (only `CONFIG_VIDEO_SONY_BTF_MPX` matches "BTF"), so the
  kernel ends up with `CONFIG_DEBUG_INFO_NONE=y`.
- Our change, appended to `debian/config/arm64/rpi/config.2712` (the 2712
  flavour is the only one the k3s nodes boot):

  ```
  CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
  CONFIG_DEBUG_INFO_BTF=y
  CONFIG_DEBUG_INFO_BTF_MODULES=y
  # CONFIG_DEBUG_INFO_REDUCED is not set
  # CONFIG_DEBUG_INFO_COMPRESSED_NONE is not set
  ```

  `DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT` selects `DEBUG_INFO`, which BTF needs;
  `DEBUG_INFO_REDUCED` is incompatible with BTF (raspberrypi/linux#6622). The
  DWARF lives in the build-tree `vmlinux` only; the installed `kernel_2712.img`
  grows by the BTF section (a few MB). `BTF_MODULES` gives every module its
  own BTF (needed for CO-RE against module types; cheap).
- Version: `1:6.18.39-1+rpt1+btf1` (`dch --local +btf`). It sorts after the
  Pi OS package and before the next Pi OS upload (`1:6.18.50-1+rpt1`), so:
  - `apt install ./linux-image-6.18.39+rpt-rpi-2712_1%3a6.18.39-1+rpt1+btf1_arm64.deb`
    is an upgrade of the installed package, same package name, same
    `uname -r` (`6.18.39+rpt-rpi-2712`), same `/lib/modules` path;
  - the existing `apt-mark hold` on the metapackages keeps Pi OS from
    replacing it with an unpatched newer kernel;
  - a future Pi OS kernel is followed by rebuilding `+btf1` for that version.
- Packages to keep from the build: `linux-image-<ver>-rpi-2712`,
  `linux-headers-<ver>-rpi-2712` (with the common headers package), and the
  `linux-image-rpi-2712` / `linux-headers-rpi-2712` metapackages if the build
  produces them at the new version (so the holds keep pointing at ours).
  `v8`, `v8-rt` and armhf flavours are not built.

### Build-time requirements

- Build-Depends from the `.dsc` (debhelper-compat 13, kernel-wedge,
  python3-dacite, python3-jinja2, quilt, plus the arch list: gcc, bc, bison,
  flex, libssl-dev, libelf-dev, rsync, kmod, cpio, lz4/zstd, …) — install with
  `apt-get build-dep` from the `.dsc` inside a `debian:trixie` arm64
  container so the toolchain matches Pi OS (gcc 14.2).
- **`dwarves` ≥ 1.22** for `pahole` (BTF encoding). trixie has 1.30. Not in
  the Pi `.dsc` Build-Depends (they never build BTF) — install it explicitly;
  the kernel's `scripts/pahole-version.sh` check fails the build otherwise.
- Disk: source tree + objects + DWARF `vmlinux` ≈ 8–12 GB (expected). Time on
  a 4-vCPU arm64 runner: 60–90 min for the 2712 flavour alone (expected;
  measure). Native on a Pi 5: 2–3 h — possible but it loads a cluster node,
  so CI is the primary path and a local x86 cross-build the fallback.

### Building one flavour only

`dpkg-buildpackage -b` builds every flavour of the architecture (v8, v8-rt,
2712) — three kernels. The Debian tooling exposes per-flavour targets after
`debian/rules debian/control` and `debian/rules.gen` are generated:

```
debian/rules orig                                   # if the tooling asks for it
debian/rules debian/control                         # (re)generate control + rules.gen
fakeroot make -f debian/rules.gen binary-arch_arm64_rpi_2712
```

To be confirmed on the first build: the exact target name in
`debian/rules.gen` (grep `binary-arch_arm64_rpi_2712`), and whether the
common headers package (`linux-headers-6.18.39+rpt-common-rpi`) is produced by
the featureset target or needs `binary-arch_arm64_rpi_real`/`binary-indep`.
Fallback: build everything (`dpkg-buildpackage -b -uc -us`) and publish only
the 2712 packages — slower, always correct.

## The build repository

Proposed name: `rpi-kernel-btf` (public, neutral: contains no infrastructure
of ours, only a build recipe). Public so that GitHub's arm64 runners are free.

```
rpi-kernel-btf/
├── README.md                 # what/why, how to use a release, current version table
├── CLAUDE.md                 # rules for a build repo
├── VERSION                   # the Pi OS source version to build, e.g. 6.18.39-1+rpt1
├── config/2712.btf           # the config fragment appended to config.2712
├── scripts/
│   ├── fetch.sh              # dget the .dsc + tarballs from archive.raspberrypi.com, verify sha256 from the .dsc
│   ├── prepare.sh            # dpkg-source -x, append fragment, dch --local +btf, record upstream Linux commit from the changelog
│   ├── build.sh              # build-dep + dwarves, build the 2712 flavour, collect *.deb + buildinfo
│   └── verify.sh             # see "Verification" below
├── .github/workflows/build.yml
└── docs/adr/                 # ADR-0001: rebuild the Pi OS kernel with BTF (why not mainline, why not the blob)
```

### GitHub Actions workflow

- Trigger: `workflow_dispatch` with input `version` (default from `VERSION`)
  and on push of a tag `v<version>+btf<n>`.
- `runs-on: ubuntu-24.04-arm`; `container: debian:trixie` (arm64) so the build
  runs on the same toolchain as Pi OS.
- Steps: fetch → prepare → build → verify → upload artifacts → on tag, create
  a GitHub Release `v6.18.39-1+rpt1+btf1` with the `.deb` files, `SHA256SUMS`,
  `buildinfo`, and a `metadata.json` (source version, upstream Linux commit
  from the changelog `Linux commit:` line, config fragment sha, pahole
  version, build date).
- ccache on the runner cache to shorten rebuilds (same upstream version, new
  `+btfN`) — optional, measure first.
- Runner limits to check on the first run: 6 h job limit (fine), ~14 GB free
  disk on the runner (tight with DWARF — clean `/usr/share/dotnet`, Android
  SDK etc. first, or build in `/mnt`).

### Verification (in CI, before anything reaches a node)

1. `dpkg-deb -c linux-image-*.deb | grep vmlinuz` and the package version.
2. BTF present in the build-tree `vmlinux`: `pahole --btf_encode_detached
   /tmp/x.btf vmlinux` succeeds, or `readelf -S vmlinux | grep .BTF`.
3. The installed image carries it: extract `/boot/vmlinuz-*` from the `.deb`,
   decompress, `bpftool btf dump file <Image> format raw | head` — the raw
   BTF magic `9f eb` must be found (`grep -obUaP '\x9f\xeb\x01\x00' Image`).
4. Module BTF: `modinfo` on a sample `.ko` shows a `.BTF` section (`readelf`).
5. `dpkg-deb -f` shows the expected `Depends`/`Provides`, and the package
   name equals the currently installed one on the nodes.

## Rollout on the cluster (cluster repo side)

Ansible, in the cluster repository:

- A role (or a mode of the existing detached-BTF role): download the release
  `.deb` for the node's flavour, verify against `SHA256SUMS`, `apt install
  ./…deb` (the Pi `z50-raspi-firmware` hooks stage it into `/boot/firmware`
  as today), keep the previous `.deb` in `/var/cache/apt/archives` for
  rollback. Holds stay.
- The serial kernel-upgrade playbook gains a source switch: `apt` (today) or
  `release` (ours). Its stage-BTF step becomes a no-op on a BTF kernel — the
  detached-BTF role already ends the host when `/sys/kernel/btf/vmlinux`
  exists — and its verification list stays valid.
- Canary: one worker node first. Install → reboot → checks:
  `ls /sys/kernel/btf/vmlinux`, `uname -r` unchanged, `vcgencmd measure_temp`
  and `/sys/class/thermal/thermal_zone0/temp` still work, fan still spins,
  `cilium-dbg status --brief` OK on 1.19.8, the `Failed to initialize
  datapath` count 0, probe pod gets an endpoint, no `one-shot job errored …
  socket-termination` line (the BPF destroyer now loads). Rollback: `apt
  install linux-image-6.18.39+rpt-rpi-2712=1:6.18.39-1+rpt1` from the cache →
  hook restores the image → reboot; or a PoE power-cycle if it does not
  boot (same recovery as today).
- Optional zero-risk variant: the `tryboot`/`os_prefix` slot mechanism from
  the mainline research works for our own kernels too (a Pi kernel can
  request tryboot), and could replace "install over the running kernel" with
  a one-shot boot. Not needed for the first canary; consider it once the
  build is routine.
- Then Cilium 1.20.x on that node only (existing OnDelete canary procedure in
  `docs/cilium.md`), then the other nodes one at a time, then Cilium fleet-wide,
  then retire the detached blob (the role stays for the record).

## Lifecycle

1. Pi OS publishes `linux 1:6.18.NN-1+rpt1` → bump `VERSION`, tag
   `v6.18.NN-1+rpt1+btf1`, CI builds and releases (≈1 h).
2. The kernel-upgrade playbook with the release source, per node: unhold,
   install the release `.deb`, reboot, verify, hold — the same serial flow as
   today; no blob step.
3. If a build fails (toolchain change, config drift), the nodes simply stay
   on the previous `+btf` kernel; nothing auto-updates.

## Effort and risk

- Effort: ~1 day to get the first green build and a verified canary; the
  workflow is reusable afterwards (bump + tag).
- Risks: (1) build reproducibility — Pi OS builds on salsa with a specific
  environment; a `debian:trixie` container on GitHub's arm64 runner is close
  but not identical (record the exact toolchain in `metadata.json`);
  (2) runner disk/time limits — measure on the first run, fall back to the
  local cross-build if needed; (3) `DEBUG_INFO` build time; (4) the
  per-flavour build target name — confirm, else build all flavours.
- Not a risk: the running kernel, its config and the Pi OS hooks are
  unchanged; rollback is reinstalling the Pi OS package.

## Decisions still open

- Repository name — settled: `rpi-kernel-btf`.
- `+btf<n>` versus a date-based suffix.
- Whether to also build `v8` (4K-page kernel) for completeness — not needed
  by the cluster.
