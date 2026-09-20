#!/usr/bin/env bash
# Layer 3: First-Boot Initialization (cloud-init / systemd-firstboot)
# x86_64 rootfs integration occurs before Layer 2 image assembly.
# Verification Class: BUILD, VM
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/init-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output}"
ROOTFS_TARBALL=""
TARGET="x86_64"
MODE="systemd-firstboot"
TEMP_DIR=""
ROOTFS=""
source "$REPO_ROOT/scripts/rootfs-ownership.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <rootfs-tar.gz> x86_64 [mode]
       $(basename "$0") <target> [mode]  (metadata-only non-x86 compatibility)
EOF
}
log() { printf '[L3-INIT] %s\n' "$*"; }
error() { printf '[L3-INIT ERROR] %s\n' "$*" >&2; exit 1; }
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
    return 0
}
trap cleanup EXIT

validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Config not found: $CONFIG_FILE"
    grep -q '^hostname:' "$CONFIG_FILE" || error "Missing hostname in configuration"
}

generate_systemd_firstboot() {
    local output_dir="$1" hostname
    hostname=$(awk '/^hostname:/ {print $2; exit}' "$CONFIG_FILE")
    : "${hostname:=ashipaos}"
    mkdir -p "$output_dir/etc/systemd"
    printf '%s\n' "$hostname" > "$output_dir/etc/hostname"
    cat > "$output_dir/etc/systemd/firstboot.conf" <<EOF
[FirstBoot]
Hostname=$hostname
Timezone=UTC
EOF
    rm -f "$output_dir/etc/machine-id"
    : > "$output_dir/etc/machine-id"
}

mutate_rootfs() {
    [[ -s "$ROOTFS_TARBALL" ]] || error "rootfs tarball not found or empty: $ROOTFS_TARBALL"
    tar -tzf "$ROOTFS_TARBALL" >/dev/null || error "rootfs is not a readable gzip tar archive"
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ashipaos-layer3-init.XXXXXX")
    ROOTFS="$TEMP_DIR/rootfs"
    mkdir -p "$ROOTFS"
    tar -xzf "$ROOTFS_TARBALL" -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*'
    generate_systemd_firstboot "$ROOTFS"
    local output="${ROOTFS_TARBALL}.init.tmp"
    tar -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' -czf "$output" .
    mv -f -- "$output" "$ROOTFS_TARBALL"
    rootfs_output_owner "$ROOTFS_TARBALL" "$(dirname "$ROOTFS_TARBALL")"
}

generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{"layer":3,"verification_class":["BUILD","VM"],"target":"$TARGET","mode":"$MODE","rootfs_integration":true}
EOF
}

main() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; return 0; }
    if [[ -f "${1:-}" ]]; then
        ROOTFS_TARBALL="$1"; TARGET="${2:-x86_64}"; MODE="${3:-systemd-firstboot}"
        [[ "$TARGET" == x86_64 ]] || error "Layer 3 rootfs integration is x86_64-only"
        validate_config; mutate_rootfs
    else
        TARGET="${1:-x86_64}"; MODE="${2:-systemd-firstboot}"
        [[ "$TARGET" == x86_64 ]] && error "x86_64 Layer 3 requires a rootfs tarball"
        validate_config; mkdir -p "$OUTPUT_DIR/init"; generate_systemd_firstboot "$OUTPUT_DIR/init"
    fi
    generate_evidence
    log "Layer 3 complete"
}
main "$@"
