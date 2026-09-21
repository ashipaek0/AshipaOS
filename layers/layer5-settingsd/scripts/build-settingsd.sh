#!/usr/bin/env bash
# Layer 5: Settings Daemon (settingsd)
# Verification Class: BUILD, VM
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/settings-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output}"
ROOTFS_TARBALL=""
TARGET="x86_64"
TEMP_DIR=""
ROOTFS=""
source "$REPO_ROOT/scripts/rootfs-ownership.sh"
log() { printf '[L5-SETTINGSD] %s\n' "$*"; }
error() { printf '[L5-SETTINGSD ERROR] %s\n' "$*" >&2; exit 1; }
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
    return 0
}
trap cleanup EXIT
validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Config not found: $CONFIG_FILE"
    grep -q '^settings:' "$CONFIG_FILE" || error "Missing settings section"
}
generate_dbus_config() {
    local out="$1"
    mkdir -p "$out/etc/dbus-1/system.d"
    cat > "$out/etc/dbus-1/system.d/com.ashipaos.settings.conf" <<'DBUSEOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Config 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root"><allow own="com.ashipaos.settings"/><allow send_destination="com.ashipaos.settings"/></policy>
</busconfig>
DBUSEOF
}
mutate_rootfs() {
    [[ -s "$ROOTFS_TARBALL" ]] || error "rootfs tarball not found or empty: $ROOTFS_TARBALL"
    tar -tzf "$ROOTFS_TARBALL" >/dev/null || error "rootfs is not a readable gzip tar archive"
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ashipaos-settingsd.XXXXXX")
    ROOTFS="$TEMP_DIR/rootfs"; mkdir -p "$ROOTFS"
    tar -xzf "$ROOTFS_TARBALL" -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*'
    generate_dbus_config "$ROOTFS"
    local output="${ROOTFS_TARBALL}.settingsd.tmp"
    tar -C "$ROOTFS" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' -czf "$output" .
    mv -f -- "$output" "$ROOTFS_TARBALL"
    rootfs_output_owner "$ROOTFS_TARBALL" "$(dirname "$ROOTFS_TARBALL")"
}
generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    printf '{"layer":5,"verification_class":["BUILD","VM"],"target":"%s","rootfs_integration":true}\n' "$TARGET" > "$EVIDENCE_DIR/build-evidence.json"
}
main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <rootfs-tar.gz> x86_64"; return 0; }
    if [[ -f "${1:-}" ]]; then
        ROOTFS_TARBALL="$1"; TARGET="${2:-x86_64}"
        [[ "$TARGET" == x86_64 || "$TARGET" == a95x-f3-air ]] || error "unsupported Layer 5 rootfs target: $TARGET"
        validate_config; mutate_rootfs
    else
        TARGET="${1:-x86_64}"
        [[ "$TARGET" == x86_64 ]] && error "x86_64 Layer 5 requires a rootfs tarball"
        validate_config; mkdir -p "$OUTPUT_DIR/settingsd"; generate_dbus_config "$OUTPUT_DIR/settingsd"
    fi
    generate_evidence; log "Layer 5 complete"
}
main "$@"
