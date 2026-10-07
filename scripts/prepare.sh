#!/usr/bin/env bash
# Unpack the source package, append the BTF config fragment to the flavour's
# config, add the +btf changelog entry and regenerate debian/control.
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FRAGMENT="$REPO_DIR/config/${FLAVOUR}.btf"
[[ -f "$FRAGMENT" ]] || die "no config fragment for flavour $FLAVOUR: $FRAGMENT"
[[ -s "$BUILD_DIR/$DSC" ]] || die "run scripts/fetch.sh first"

cd "$BUILD_DIR"
rm -rf "$SOURCE_DIR"
log "unpacking $DSC"
dpkg-source --no-check -x "$DSC" "$SOURCE_DIR" >/dev/null
cd "$SOURCE_DIR"

CONFIG="debian/config/arm64/rpi/config.${FLAVOUR}"
[[ -f "$CONFIG" ]] || die "flavour config not found: $CONFIG"
grep -q 'CONFIG_DEBUG_INFO_BTF' "$CONFIG" && die "$CONFIG already carries BTF options"
{
  echo
  echo "# --- rpi-kernel-btf: $(basename "$FRAGMENT") ---"
  grep -v '^#' "$FRAGMENT" | grep -v '^$'
} >> "$CONFIG"
log "appended $(grep -c '^CONFIG_' "$FRAGMENT") options to $CONFIG"

# Upstream Linux commit the Pi OS package was cut from (for metadata.json).
LINUX_COMMIT="$(sed -n 's/^  \* Linux commit: \([0-9a-f]\{40\}\).*/\1/p' debian/changelog | head -1)"
[[ -n "$LINUX_COMMIT" ]] || log "warning: no 'Linux commit:' line in the changelog"

# Amend the top changelog stanza instead of adding one: gencontrol counts the
# stanzas that share an upstream version and distribution and appends "+N" to
# the ABI name for the second one, which would rename every package and change
# uname -r. Rewriting the version in place keeps the ABI (and the names) of
# the Pi OS upload; only the Debian revision grows a +btf suffix, so it sorts
# after the package it was built from.
TOP_VERSION="$(dpkg-parsechangelog -S Version)"
[[ "$TOP_VERSION" == "${EPOCH}:${PIOS_VERSION}" ]] || die "changelog top is $TOP_VERSION, expected ${EPOCH}:${PIOS_VERSION}"
NOTE_1="  * Rebuild with CONFIG_DEBUG_INFO_BTF=y for flavour ${FLAVOUR} (rpi-kernel-btf;"
NOTE_2="    config fragment $(basename "$FRAGMENT"), sha256 $(sha256sum "$FRAGMENT" | cut -c1-12))."
awk -v old="linux (${EPOCH}:${PIOS_VERSION})" -v new="linux (${EPOCH}:${BTF_VERSION})" \
    -v n1="$NOTE_1" -v n2="$NOTE_2" '
  NR==1 && index($0, old)==1 { sub(/^linux \([^)]*\)/, new); print; getline; print; print n1; print n2; next }
  { print }' debian/changelog > debian/changelog.new
mv debian/changelog.new debian/changelog
log "changelog: $(dpkg-parsechangelog -S Version)"

# debian/control and debian/rules.gen are generated from the changelog and the
# defines; the packaging refuses to build with a stale control.md5sum. The
# first run regenerates and exits non-zero on purpose, the second confirms.
make -f debian/rules debian/control >/dev/null 2>&1 || true
make -f debian/rules debian/control >/dev/null
grep -q "^Version: ${EPOCH}:${BTF_VERSION}\$" <(dpkg-parsechangelog) || die "changelog version mismatch"
grep -q "^binary-arch_arm64_rpi_${FLAVOUR}:" debian/rules.gen || die "no target for flavour $FLAVOUR in rules.gen"
log "control regenerated; targets for flavour $FLAVOUR present"

mkdir -p "$OUT_DIR"
cat > "$OUT_DIR/metadata.json" <<JSON
{
  "pios_version": "${EPOCH}:${PIOS_VERSION}",
  "btf_version": "${EPOCH}:${BTF_VERSION}",
  "upstream_version": "${UPSTREAM_VERSION}",
  "flavour": "${FLAVOUR}",
  "linux_commit": "${LINUX_COMMIT:-unknown}",
  "config_fragment": "$(basename "$FRAGMENT")",
  "config_fragment_sha256": "$(sha256sum "$FRAGMENT" | cut -d' ' -f1)",
  "source_dsc_sha256": "$(sha256sum "$BUILD_DIR/$DSC" | cut -d' ' -f1)"
}
JSON
log "wrote $OUT_DIR/metadata.json"
