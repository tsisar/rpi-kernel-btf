# ADR-0003: Enable the socket diag options Cilium needs

- Status: Accepted
- Date: 2026-10-08
- Deciders: Pavlo Tsisar

## Context

With BTF in the kernel, Cilium 1.20 loads its datapath on the Pi 5. At start
it probes one more kernel facility: to terminate client sockets still
connected to a removed service backend it lists UDP sockets through netlink
`INET_DIAG` and closes them with `SOCK_DESTROY`. The Pi OS config has
`CONFIG_INET_DIAG=m` but neither `CONFIG_INET_UDP_DIAG` nor
`CONFIG_INET_DIAG_DESTROY`, so the agent logs

    Forcefully terminating sockets connected to deleted service backends not
    supported by underlying kernel … (CONFIG_INET_UDP_DIAG)

and keeps running without the feature: a client holding a UDP "connection"
(DNS, for one) to a backend that went away keeps sending into the void until
it times out on its own.

This repository already carries a config fragment for the one option Pi OS
lacks; the question is whether it may carry more than BTF.

## Decision

We will add `CONFIG_INET_UDP_DIAG=m` and `CONFIG_INET_DIAG_DESTROY=y` to the
2712 fragment and rebuild the same Pi OS version as `+btf2`. The fragment is
"what the cluster's CNI needs from the kernel and Pi OS does not provide",
not "BTF only"; every addition is recorded here with the Cilium behaviour
that needs it.

## Consequences

- Cilium's socket termination works; the agent no longer logs the error.
- `udp_diag` is a module like `inet_diag`; the kernel autoloads it on the
  first UDP diag request, no modules-load entry is needed.
- `SOCK_DESTROY` is available to any privileged process (`ss -K`), which is
  the kernel's default on every mainstream distribution.
- A `SUFFIX` file now carries the local suffix, so a rebuild of the same Pi
  OS version is a one-line bump.

## Alternatives considered

### Leave it

The feature is a nicety; the cluster ran without it on 1.19 and the blob.
Rejected because the rebuild is cheap once the pipeline exists, and a
startup error in every agent log is noise that hides real errors.

### Build the diag options in (`=y`)

`INET_UDP_DIAG` is tristate and depends on `INET_DIAG`, which Pi OS sets
to `=m`; making both built-in changes more of the Pi config than needed.
`=m` with autoload is equivalent in practice.
