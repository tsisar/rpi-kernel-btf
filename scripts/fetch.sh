#!/usr/bin/env bash
# Download the Pi OS kernel source package named in VERSION into BUILD_DIR and
# verify every file against the sha256 sums carried by the .dsc.
# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

fetch() {
  local name="$1"
  if [[ -s "$name" ]]; then
    log "have $name"
  else
    log "fetching $name"
    curl -fsSL --retry 3 --retry-delay 5 -o "$name.part" "$ARCHIVE_URL/$name"
    mv "$name.part" "$name"
  fi
}

fetch "$DSC"

# The .dsc lists its companions with sizes and sha256 sums; take both from there
# rather than guessing names, then verify.
awk '/^Checksums-Sha256:/{f=1; next} /^[A-Za-z-]+:/{f=0} f && NF==3 {print $1, $3}' "$DSC" \
  | while read -r sum name; do
      fetch "$name"
      echo "$sum  $name" | sha256sum -c --quiet - || die "sha256 mismatch for $name"
      log "verified $name"
    done

ls -l "$DSC" "$ORIG_TARBALL" "$DEBIAN_TARBALL" >&2
