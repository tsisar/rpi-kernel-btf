#!/usr/bin/env bash
# Build the image, headers, base and meta packages of one flavour from the
# prepared source tree. Runs inside a Debian trixie arm64 environment as root
# (build-dep installation) — see docs/building.md.
#
# Deliberately not built: the -dbg package (a vmlinux with full DWARF, ~1 GB,
# nothing on a node needs it), the other flavours, tools and docs.
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ -f "$SOURCE_DIR/debian/rules.gen" ]] || die "run scripts/prepare.sh first"
[[ "$(dpkg --print-architecture)" == "arm64" ]] || die "must run on arm64 (got $(dpkg --print-architecture))"

JOBS="${JOBS:-$(nproc)}"
export DEB_BUILD_PROFILES="${DEB_BUILD_PROFILES:-nodoc pkg.linux.notools}"
export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"
export DEBIAN_KERNEL_JOBS="$JOBS"

if [[ "${SKIP_DEPS:-0}" != "1" ]]; then
  log "installing build dependencies (profiles: $DEB_BUILD_PROFILES)"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    build-essential fakeroot dpkg-dev dwarves bpftool kmod zstd xz-utils file >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -qq "$BUILD_DIR/$DSC" >/dev/null
fi
log "pahole $(pahole --version) gcc $(gcc -dumpfullversion) jobs $JOBS"

cd "$SOURCE_DIR"
start=$(date +%s)

# The packaging's own flow: apply the featureset patches, then build and
# package exactly the sub-targets this flavour needs.
targets_build=()
targets_binary=()
for part in base headers image meta; do
  targets_build+=("build-arch_arm64_rpi_${FLAVOUR}_${part}")
  targets_binary+=("binary-arch_arm64_rpi_${FLAVOUR}_${part}")
done
# arch-independent common headers the flavour headers depend on
targets_binary+=("binary-indep_rpi_headers-common")

log "source: applying featureset patches"
fakeroot make -f debian/rules.gen source
log "build: ${targets_build[*]}"
fakeroot make -f debian/rules.gen "${targets_build[@]}"
log "binary: ${targets_binary[*]}"
fakeroot make -f debian/rules.gen "${targets_binary[@]}"

end=$(date +%s)
mkdir -p "$OUT_DIR"
mv "$BUILD_DIR"/*.deb "$OUT_DIR"/ 2>/dev/null || true
# the meta sub-target also emits the -dbg metapackage; it depends on a package
# this build never produces, so it must not reach a release
rm -f "$OUT_DIR"/linux-image-rpi-*-dbg_*.deb
cp "$SOURCE_DIR/debian/build/build_arm64_rpi_${FLAVOUR}/.config" "$OUT_DIR/config-${FLAVOUR}" 2>/dev/null || true

# build info for the release
{
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "build_seconds=$((end - start))"
  echo "jobs=$JOBS"
  echo "gcc=$(gcc -dumpfullversion)"
  echo "pahole=$(pahole --version)"
  echo "debian=$(cat /etc/debian_version)"
} > "$OUT_DIR/buildinfo.txt"
(cd "$OUT_DIR" && sha256sum ./*.deb > SHA256SUMS)
log "done in $((end - start)) s"
ls -l "$OUT_DIR" >&2
