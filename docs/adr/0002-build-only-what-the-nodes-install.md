# ADR-0002: Build only what the nodes install

- Status: Accepted
- Date: 2026-10-07
- Deciders: Pavlo Tsisar

## Context

The Pi OS `linux` source package builds five kernel flavours (`2712`, `v8`,
`v8-rt` on arm64; `v6`, `v7` on armhf), a `-dbg` package per flavour, and a
long tail of tools and documentation. A full `dpkg-buildpackage` is several
kernel builds and tens of gigabytes. With `CONFIG_DEBUG_INFO_BTF=y` every
object carries DWARF, which multiplies the build tree; a hosted GitHub runner
has four cores, a six-hour job limit and a few tens of gigabytes of disk.

The nodes this repository serves are Raspberry Pi 5 boards running the
`2712` flavour. Nothing on them needs the debug symbols.

## Decision

We will build, from the regenerated `debian/rules.gen`, only the `2712`
flavour's `base`, `headers`, `image` and `meta` sub-targets plus the
arch-independent `linux-headers-<abi>-common-rpi`, with the build profiles
`nodoc pkg.linux.notools`. The `-dbg` sub-target is never invoked. DWARF is
compressed in the build tree (`CONFIG_DEBUG_INFO_COMPRESSED_ZLIB=y`), which
BTF generation tolerates, to keep the tree within the runner's disk.

## Consequences

- One kernel build per run instead of three; the run fits the runner.
- The release contains exactly the packages a node installs, same names as
  Pi OS, so holds and dependencies keep working.
- `v8` (4K-page) users would need a second flavour added to the scripts; the
  scripts take `FLAVOUR` for that, the workflow does not loop over it yet.
- No `-dbg` package means no `vmlinux` with symbols for crash analysis; the
  build-tree `vmlinux` is not published either.

## Alternatives considered

### `dpkg-buildpackage -b` (everything)

Correct by construction, but three arm64 kernels with DWARF do not fit the
runner's time and disk, and four fifths of the output would be discarded.

### Keep the `-dbg` package

It is the one artifact that would make the release gigabytes; nobody on the
nodes consumes it, and a `vmlinux` can be rebuilt from the same inputs if a
crash ever needs one.

### Uncompressed DWARF

Simpler and the kernel default, but roughly four times the disk during the
build; the compressed form is supported by `pahole` ≥ 1.22 and changes
nothing in the produced BTF.
