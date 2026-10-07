# ADR-0001: Rebuild the Pi OS kernel with BTF

- Status: Accepted
- Date: 2026-10-07
- Deciders: Pavlo Tsisar

## Context

A Raspberry Pi 5 Kubernetes cluster runs Cilium as its CNI. Cilium 1.20 made its
SNAT helpers global BPF subprograms; the kernel verifier validates their `ctx`
argument against the kernel's own vmlinux BTF (`btf_validate_prog_ctx_type`),
and its socket-termination path is a BPF iterator the kernel resolves the same
way. Without in-kernel BTF the host endpoint never regenerates. Every Cilium
patch release since 2026-09-15 additionally needs CO-RE for socket-LB.

Raspberry Pi OS kernels are built with `CONFIG_DEBUG_INFO_NONE=y`; the
maintainers have declined to enable BTF (raspberrypi/linux#6622). The cluster
currently runs Cilium 1.19.8 on a detached BTF blob under `/lib/modules`, which
serves user-space CO-RE relocations only — a hard ceiling at the 1.19 line.

The cluster needs what the Pi OS kernel provides and mainline does not: the
BCM2712 thermal zone and fan control (the Active Cooler is off and the SoC
temperature is invisible on a mainline kernel), `vcgencmd`, 16K pages, device
tree overlays and the `raspi-firmware` boot hooks.

## Decision

We will rebuild the unmodified Raspberry Pi OS kernel source package
(`linux_<ver>-1+rpt1`) for the `2712` flavour with
`CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y`, `CONFIG_DEBUG_INFO_BTF=y` and
`CONFIG_DEBUG_INFO_BTF_MODULES=y` appended to the flavour's config, versioned
`<ver>-1+rpt1+btf<n>` so the package name and `uname -r` stay those of Pi OS.
The build runs in GitHub Actions on an arm64 runner inside a `debian:trixie`
container with `dwarves` installed, and publishes a GitHub Release per version.

## Consequences

- Cilium 1.20+ becomes possible; the detached-blob workaround can be retired.
- Everything else about the node kernel is unchanged: same config, drivers,
  firmware hooks, thermal and fan behaviour; rollback is the Pi OS package.
- Each Pi OS kernel upload needs a rebuild (bump `VERSION`, tag) before the
  nodes can follow it; `apt-mark hold` protects the custom build meanwhile.
- The kernel image grows by the BTF section (a few MB); DWARF stays in the
  build tree.
- The build environment is close to, not identical with, Pi OS's; the
  release records the toolchain so a difference can be diagnosed.

## Alternatives considered

### Detached BTF blob (current state)

A raw BTF blob at `/lib/modules/<release>/vmlinux-<release>` makes
cilium/ebpf's loader find a kernel spec. It gets Cilium to 1.19.8 and no
further: the verifier and BPF iterators use in-kernel BTF only. Kept as the
interim state, not a path forward.

### Debian mainline arm64 kernel (trixie-backports)

Ships BTF and boots the Pi 5 (RP1, PCIe, NVMe, cpufreq present) but has no
thermal zone and no fan driver for the board, `vcgencmd` is broken, and the
Pi firmware's `tryboot` can only be requested from a Pi kernel. Rejected
because temperature monitoring and fan control are non-negotiable.

### Wait for upstream

raspberrypi/linux#6622 is open since 2025-01 with a maintainer stating the
answer is likely no; Cilium's probe-and-fallback PR (#45626) was closed
unmerged. No timeline to wait for.

### Ubuntu `linux-raspi`

No BTF in the 24.04 kernel; moving the node OS for a kernel option is a far
larger change than rebuilding one package.
