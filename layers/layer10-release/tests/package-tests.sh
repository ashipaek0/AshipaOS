#!/usr/bin/env bash
set -Eeuo pipefail

LAYER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$LAYER_DIR/scripts/build-10-release.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/empty" "$TMP_DIR/release/images" "$TMP_DIR/evidence"
if OUTPUT_DIR="$TMP_DIR/empty" ASHIPAOS_RELEASE_EVIDENCE_DIR="$TMP_DIR/evidence" \
    "$BUILD_SCRIPT" x86_64 >/dev/null 2>&1; then
    echo "release packaging accepted a missing Layer 2 image" >&2
    exit 1
fi
[[ ! -e "$TMP_DIR/evidence/build-evidence.json" ]] || {
    echo "failed packaging emitted false PASS evidence" >&2
    exit 1
}

printf 'partitioned-image\n' >"$TMP_DIR/release/images/ashipaos-x86_64-test.img"
OUTPUT_DIR="$TMP_DIR/release" ASHIPAOS_RELEASE_EVIDENCE_DIR="$TMP_DIR/evidence" VERSION=0.0.1-dev \
    "$BUILD_SCRIPT" x86_64 >/dev/null

gzip -t "$TMP_DIR/release/images/ashipaos-x86_64-test.img.gz"
(cd "$TMP_DIR/release/images" && sha256sum --check SHA256SUMS-x86_64 >/dev/null)
(cd "$TMP_DIR/release/ota" && sha256sum --check SHA256SUMS-x86_64 >/dev/null)
[[ -s "$TMP_DIR/release/ota/ashipaos-x86_64-test-0.0.1-dev.pkg" ]]
[[ "$(jq -r '.result' "$TMP_DIR/evidence/build-evidence.json")" == PASS ]]

echo "Layer 10 package tests passed"
