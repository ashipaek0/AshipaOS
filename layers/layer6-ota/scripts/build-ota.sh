#!/usr/bin/env bash
# Layer 6: OTA Update Mechanism
# Verification Class: BUILD, HARDWARE
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/ota-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output}"
ROOTFS_TARBALL=""
TARGET="x86_64"
TEMP_DIR=""
ROOTFS=""
source "$REPO_ROOT/scripts/rootfs-ownership.sh"
log() { printf '[L6-OTA] %s\n' "$*"; }
error() { printf '[L6-OTA ERROR] %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf -- "$TEMP_DIR"; }
trap cleanup EXIT
validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Config not found: $CONFIG_FILE"
    grep -q '^ota:' "$CONFIG_FILE" || error "Missing ota section"
}
generate_ota_manifest() {
    local out="$1"
    mkdir -p "$out/etc/ota"
    cat > "$out/etc/ota/manifest.json" <<'MANIFESTEOF'
{"version":"1.0","slots":{"a":"active","b":"inactive"},"update_policy":"A/B"}
MANIFESTEOF
}
mutate_rootfs() {
    [[ -s "$ROOTFS_TARBALL" ]] || error "rootfs tarball not found or empty: $ROOTFS_TARBALL"
    tar -tzf "$ROOTFS_TARBALL" >/dev/null || error "rootfs is not a readable gzip tar archive"
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ashipaos-ota.XXXXXX")
    ROOTFS="$TEMP_DIR/rootfs"; mkdir -p "$ROOTFS"
    tar -xzf "$ROOTFS_TARBALL" -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*'
    generate_ota_manifest "$ROOTFS"
    local output="${ROOTFS_TARBALL}.ota.tmp"
    tar -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' -czf "$output" .
    mv -f -- "$output" "$ROOTFS_TARBALL"
    rootfs_output_owner "$ROOTFS_TARBALL" "$(dirname "$ROOTFS_TARBALL")"
    mkdir -p "$OUTPUT_DIR/ota"
    install -m 0644 "$ROOTFS/etc/ota/manifest.json" "$OUTPUT_DIR/ota/manifest.json"
    sha256sum "$OUTPUT_DIR/ota/manifest.json" > "$OUTPUT_DIR/ota/manifest.json.sha256"
}
generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    printf '{"layer":6,"verification_class":["BUILD","HARDWARE"],"target":"%s","rootfs_integration":true,"manifest":"output/ota/manifest.json"}\n' "$TARGET" > "$EVIDENCE_DIR/build-evidence.json"
}
main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <rootfs-tar.gz> x86_64"; return 0; }
    if [[ -f "${1:-}" ]]; then
        ROOTFS_TARBALL="$1"; TARGET="${2:-x86_64}"
        [[ "$TARGET" == x86_64 ]] || error "Layer 6 rootfs integration is x86_64-only"
        validate_config; mutate_rootfs
    else
        TARGET="${1:-x86_64}"
        [[ "$TARGET" == x86_64 ]] && error "x86_64 Layer 6 requires a rootfs tarball"
        validate_config; mkdir -p "$OUTPUT_DIR/ota"; generate_ota_manifest "$OUTPUT_DIR/ota"; sha256sum "$OUTPUT_DIR/ota/manifest.json" > "$OUTPUT_DIR/ota/manifest.json.sha256"
    fi
    generate_evidence; log "Layer 6 complete"
}
main "$@"
