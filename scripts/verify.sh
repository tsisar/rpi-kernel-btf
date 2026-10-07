#!/usr/bin/env bash
# Prove the produced packages carry BTF and keep the Pi OS names:
#   1. the build-tree vmlinux has a .BTF section bpftool can parse,
#   2. the kernel image inside the .deb carries the raw BTF header (9f eb 01 00),
#   3. a module inside the .deb has a .BTF section,
#   4. package name, ABI name and version are what the plan promises.
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# The ABI name the packaging settled on (e.g. 6.18.50+rpt) names every package.
ABINAME="$(grep -o -m1 "ABINAME='[^']*'" "$SOURCE_DIR/debian/rules.gen" | cut -d"'" -f2)"
[[ -n "$ABINAME" ]] || die "cannot read ABINAME from rules.gen"

IMAGE_DEB=""
for f in "$OUT_DIR"/linux-image-*-rpi-"${FLAVOUR}"_*.deb; do
  [[ -f "$f" && "$f" != *-dbg_* ]] && IMAGE_DEB="$f" && break
done
[[ -n "$IMAGE_DEB" ]] || die "no image package in $OUT_DIR"
log "image package: $(basename "$IMAGE_DEB")"

fail=0
# check <description> <command...>
check() {
  local msg="$1"; shift
  if "$@"; then log "ok:   $msg"; else log "FAIL: $msg"; fail=1; fi
}

# 1. build-tree vmlinux (present after build.sh, absent when verifying a downloaded artifact)
VMLINUX="$SOURCE_DIR/debian/build/build_arm64_rpi_${FLAVOUR}/vmlinux"
if [[ -f "$VMLINUX" ]]; then
  check "vmlinux has a .BTF section" sh -c "readelf -S '$VMLINUX' | grep -q ' \.BTF '"
  check "bpftool parses vmlinux BTF (task_struct present)" \
    sh -c "bpftool btf dump file '$VMLINUX' format raw | grep -q 'STRUCT .task_struct'"
else
  log "skip: build-tree vmlinux not present"
fi

# 2 + 3. the shipped image and a module
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
dpkg-deb -x "$IMAGE_DEB" "$TMP"
# -print -quit, not "| head -1": with pipefail, head closing the pipe makes find die of SIGPIPE (exit 141)
KIMG="$(find "$TMP/boot" -maxdepth 1 -name 'vmlinuz-*' -print -quit)"
[[ -n "$KIMG" ]] || die "no /boot/vmlinuz-* in the package"
log "kernel image: $(basename "$KIMG") ($(stat -c %s "$KIMG") bytes)"
if file "$KIMG" | grep -q gzip; then gzip -dc "$KIMG" > "$TMP/Image"; else cp "$KIMG" "$TMP/Image"; fi
check "raw BTF magic present in the kernel Image" \
  sh -c "grep -obUaP '\x9f\xeb\x01\x00' '$TMP/Image' | head -1 | grep -q ."

# merged-/usr packages ship modules under usr/lib/modules; older ones under lib/modules
MODROOT=""
for d in "$TMP/usr/lib/modules" "$TMP/lib/modules"; do [[ -d "$d" ]] && MODROOT="$d" && break; done
[[ -n "$MODROOT" ]] || die "no modules directory in the package"
MOD="$(find "$MODROOT" -name 'cfg80211.ko*' -print -quit)"
[[ -n "$MOD" ]] || MOD="$(find "$MODROOT" -name '*.ko*' -print -quit)"
[[ -n "$MOD" ]] || die "no modules found under $MODROOT"
case "$MOD" in
  *.ko.xz)  xz -dc "$MOD" > "$TMP/mod.ko" ;;
  *.ko.zst) zstd -dcq "$MOD" > "$TMP/mod.ko" ;;
  *.ko.gz)  gzip -dc "$MOD" > "$TMP/mod.ko" ;;
  *)        cp "$MOD" "$TMP/mod.ko" ;;
esac
check "module $(basename "$MOD") has a .BTF section" sh -c "readelf -S '$TMP/mod.ko' | grep -q ' \.BTF '"
check "shipped config has CONFIG_DEBUG_INFO_BTF=y" sh -c "grep -q '^CONFIG_DEBUG_INFO_BTF=y' '$TMP'/boot/config-*"

# 4. names and versions
PKG="$(dpkg-deb -f "$IMAGE_DEB" Package)"
VER="$(dpkg-deb -f "$IMAGE_DEB" Version)"
check "ABI name unchanged from Pi OS (${UPSTREAM_VERSION}+rpt, got $ABINAME)" test "$ABINAME" = "${UPSTREAM_VERSION}+rpt"
check "package name is linux-image-${ABINAME}-rpi-${FLAVOUR} (got $PKG)" test "$PKG" = "linux-image-${ABINAME}-rpi-${FLAVOUR}"
check "package version is ${EPOCH}:${BTF_VERSION} (got $VER)" test "$VER" = "${EPOCH}:${BTF_VERSION}"
check "headers package present" sh -c "ls '$OUT_DIR'/linux-headers-*-rpi-${FLAVOUR}_*.deb >/dev/null"
check "image metapackage present" sh -c "ls '$OUT_DIR'/linux-image-rpi-${FLAVOUR}_*.deb >/dev/null"
check "no -dbg metapackage in the output" sh -c "! ls '$OUT_DIR'/linux-image-rpi-*-dbg_*.deb >/dev/null 2>&1"

[[ $fail -eq 0 ]] || die "verification failed"
log "all checks passed"
