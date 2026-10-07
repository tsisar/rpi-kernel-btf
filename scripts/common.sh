#!/usr/bin/env bash
# Shared settings for the build scripts. Sourced, not executed.
#
# Inputs:
#   VERSION file   - Pi OS source version, e.g. 6.18.50-1+rpt1
#   BTF_SUFFIX     - local version suffix appended to it (default: +btf1)
#   FLAVOUR        - Pi OS kernel flavour to build (default: 2712)
#   BUILD_DIR      - working directory (default: ./build)
# shellcheck disable=SC2034  # variables are consumed by the sourcing scripts
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build}"
FLAVOUR="${FLAVOUR:-2712}"
BTF_SUFFIX="${BTF_SUFFIX:-+btf1}"
ARCHIVE_URL="${ARCHIVE_URL:-http://archive.raspberrypi.com/debian/pool/main/l/linux}"

PIOS_VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"       # 6.18.50-1+rpt1
UPSTREAM_VERSION="${PIOS_VERSION%%-*}"                            # 6.18.50
BTF_VERSION="${PIOS_VERSION}${BTF_SUFFIX}"                        # 6.18.50-1+rpt1+btf1
EPOCH="1"                                                         # Pi OS linux carries epoch 1

DSC="linux_${PIOS_VERSION}.dsc"
ORIG_TARBALL="linux_${UPSTREAM_VERSION}.orig.tar.xz"
DEBIAN_TARBALL="linux_${PIOS_VERSION}.debian.tar.xz"
SOURCE_DIR="$BUILD_DIR/linux-${UPSTREAM_VERSION}"
OUT_DIR="$BUILD_DIR/out"

log() { printf '[%s] %s\n' "$(basename "$0")" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
