# CLAUDE.md

Guidance for Claude Code working in this repository.

# Project

`rpi-kernel-btf` builds Raspberry Pi OS kernel packages for the Pi 5 with
`CONFIG_DEBUG_INFO_BTF=y`, from the unmodified Pi OS source package, in GitHub
Actions. It contains a build recipe and nothing else: no infrastructure, no
addresses, no secrets. The output is a GitHub Release of `.deb` files that a
separate (private) cluster repository installs on its nodes.

Consequences:

- A change is "done" when the workflow is green **and** `scripts/verify.sh`
  proved BTF is in the shipped `Image` — not when the scripts look right.
- The build must stay reproducible from `VERSION` + `config/2712.btf` alone;
  no hand-made artifacts, nothing downloaded outside `scripts/fetch.sh`.
- Pi OS packaging is Debian kernel packaging: read `debian/config/arm64/rpi/`,
  `debian/config/arm64/defines.toml` and `debian/rules.gen` of the extracted
  source before guessing at flavours or targets. Confirm the per-flavour
  target name on the first build; building every flavour is the fallback.

# Working mode

- Work on a branch (`feat/<kebab>`, `fix/<kebab>`, `docs/<kebab>`, `ci/<kebab>`),
  commit as you go, push the branch, open a pull request with the workflow
  result linked. **Do not push to `master` directly** — the owner merges.
- Run the workflow yourself (`gh workflow run` / push) and read its log; a
  red run is yours to diagnose before asking anything.
- Record measured facts (build time, disk, pahole version, Image size delta)
  in `docs/plan.md` replacing the "expected" numbers, in the same PR.

# Quality gates

1. `shellcheck` clean for every script; scripts are `set -euo pipefail`,
   idempotent and runnable locally in a `debian:trixie` arm64 container.
2. `actionlint` clean for the workflow.
3. `scripts/verify.sh` passes on the produced packages.
4. README describes the current state (what exists, how to use a release);
   `docs/plan.md` is the plan; new non-trivial decisions get an ADR in
   `docs/adr/` (Nygard template + "Alternatives considered", append-only,
   index in `docs/adr/README.md` updated in the same commit).
5. No secrets, tokens or keys in the diff. Public repository.

# Conventional Commits

All commit messages follow Conventional Commits 1.0.0:
`<type>[scope]: <description>` — lowercase, imperative, no trailing period,
first line under 72 characters, body says *why*. Types: `feat`, `fix`, `docs`,
`ci`, `build` (version bumps in `VERSION`, toolchain), `chore`, `refactor`,
`test`, `revert`. Scopes: `fetch`, `prepare`, `build`, `verify`, `workflow`,
`config`, `release`. All content in English. No `Co-Authored-By` lines.

# Secrets and neutrality

This is a public repository. Nothing that grants access goes into git, and
nothing that describes the owner's network: no LAN addresses, hostnames,
node names, router details or private repository URLs. Upstream project
domains, download URLs, kernel strings and versions are fine.
