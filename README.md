# rpi-kernel-btf

Raspberry Pi OS kernel packages for the Pi 5 (`2712` flavour) rebuilt from the
unmodified Pi OS source package with one change: `CONFIG_DEBUG_INFO_BTF=y`.

Cilium ≥ 1.20 needs BTF inside the kernel (its global BPF subprograms are
verified against the kernel's own vmlinux BTF); Raspberry Pi does not ship it
(raspberrypi/linux#6622) and a detached BTF blob only gets as far as Cilium
1.19. Debian's mainline arm64 kernel has BTF but no thermal zone or fan control
on the Pi 5. So: same kernel, same config, same `uname -r`, plus BTF.
`docs/adr/0001-rebuild-the-pi-os-kernel-with-btf.md` records why.

## Status

Building and releasing. `docs/building.md` describes the scripts and how to
run them locally; `docs/plan.md` is the plan they implement.

| Release | Pi OS source | Linux commit | Flavour | Built |
|---|---|---|---|---|
| [v6.18.50-1+rpt1+btf1](https://github.com/tsisar/rpi-kernel-btf/releases/tag/v6.18.50-1%2Brpt1%2Bbtf1) | `1:6.18.50-1+rpt1` | `cff533aec2fa` | 2712 | 2026-10-07, 1 h 54 min |
| [v6.18.50-1+rpt1+btf2](https://github.com/tsisar/rpi-kernel-btf/releases/tag/v6.18.50-1%2Brpt1%2Bbtf2) | `1:6.18.50-1+rpt1` | `cff533aec2fa` | 2712 | 2026-10-08; adds `INET_UDP_DIAG`, `INET_DIAG_DESTROY` (ADR-0003) |

## Layout

```
VERSION                     # the Pi OS source version to build, e.g. 6.18.50-1+rpt1
config/2712.btf             # config fragment appended to the 2712 flavour
scripts/fetch.sh            # .dsc + tarballs from archive.raspberrypi.com, sha256 from the .dsc
scripts/prepare.sh          # dpkg-source -x, append fragment, dch --local +btf
scripts/build.sh            # build-dep + dwarves, build the 2712 flavour, collect *.deb
scripts/verify.sh           # BTF present in vmlinux, in the shipped Image, in modules
.github/workflows/build.yml # ubuntu-24.04-arm runner, debian:trixie container, release on tag
docs/plan.md                # the plan the scripts implement
docs/adr/                   # decisions
```

## Using a release

A release `v<version>+btf<n>` carries the `linux-image-*-rpi-2712` and
`linux-headers-*-rpi-2712` `.deb` files, `SHA256SUMS`, the `.buildinfo` and a
`metadata.json` (source version, upstream Linux commit, config fragment hash,
pahole version). On a node:

```
apt install ./linux-image-<ver>-rpi-2712_<ver>+btf<n>_arm64.deb
reboot
ls /sys/kernel/btf/vmlinux
```

The package name and `uname -r` equal the Pi OS ones, so an `apt-mark hold` on
`linux-image-rpi-2712` keeps Pi OS from replacing it. Rollback is reinstalling
the Pi OS package of the same version.
