#!/usr/bin/env bash
# Layer 10: Release engineering for the A95X F3 Air image.
# Verification Class: BUILD (gzip + SHA-256 only; signing is scripts/ci-sign-artefacts.sh)
#
# Consumes the raw Layer 2 image(s) and produces exactly what the CI signing,
# upload and release steps look for:
#   output/images/ashipaos-<target>-<date>.img.gz
#   output/images/SHA256SUMS-<target>
# It fails if there is no image: a release step that succeeds without an image
# is what previously let green runs upload nothing.
#
# OTA (.pkg) packaging is NOT implemented yet (contracts/release.md is a stub).
# This script says so explicitly instead of printing a fake PASS.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
IMAGES_DIR="${GITHUB_WORKSPACE:-$REPO_ROOT}/output/images"
DEFAULT_TARGET="a95x-f3-air"

log() { printf '[L10-RELEASE] %s\n' "$*"; }
error() { printf '[L10-RELEASE ERROR] %s\n' "$*" >&2; exit 1; }

target="${1:-$DEFAULT_TARGET}"
[[ "$target" == "$DEFAULT_TARGET" ]] || error "Only $DEFAULT_TARGET is supported (got: $target)"
[[ -d "$IMAGES_DIR" ]] || error "Layer 2 output directory not found: $IMAGES_DIR"

count=0
for img in "$IMAGES_DIR"/ashipaos-"${target}"-*.img; do
    [[ -f "$img" ]] || continue
    [[ -s "$img" ]] || error "Layer 2 image is empty: $img"
    log "Compressing $(basename "$img")"
    # -n: no name/timestamp in the gzip header, so the archive is reproducible.
    gzip -9 -n -c -- "$img" >"$img.gz.partial"
    gzip -t -- "$img.gz.partial" || error "gzip integrity check failed: $img"
    mv -f -- "$img.gz.partial" "$img.gz"
    count=$((count + 1))
done
(( count > 0 )) || error "no ashipaos-${target}-*.img found in $IMAGES_DIR; refusing to publish a release without an image"

(
    cd "$IMAGES_DIR"
    sha256sum -- ashipaos-"${target}"-*.img.gz >"SHA256SUMS-${target}"
    sha256sum --check --strict "SHA256SUMS-${target}"
)

log "OTA packages: not built (OTA packaging is not implemented; no .pkg emitted)"
log "Release artefacts ready in $IMAGES_DIR:"
ls -lh -- "$IMAGES_DIR"
