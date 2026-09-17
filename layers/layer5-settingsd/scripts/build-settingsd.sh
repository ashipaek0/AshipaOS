#!/bin/bash
# Layer 5: Settings Daemon (settingsd)
# Verification Class: BUILD, VM
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/settings-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
REPO_ROOT="$(cd "$LAYER_DIR/../../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output}"
TARGET="${1:-x86_64}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Config not found: $CONFIG_FILE"
    grep -q "settings:" "$CONFIG_FILE" || error "Missing settings section"
    log "Configuration valid"
}
generate_dbus_config() {
    local out="$1"
    mkdir -p "$out/etc/dbus-1/system.d"
    cat > "$out/etc/dbus-1/system.d/com.ashipaos.settings.conf" << 'DBUSEOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Config 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root"><allow own="com.ashipaos.settings"/><allow send_destination="com.ashipaos.settings"/></policy>
</busconfig>
DBUSEOF
    log "Generated D-Bus configuration"
}
generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    cat > "$EVIDENCE_DIR/build-evidence.json" << EOFEOL
{"layer":5,"verification_class":["BUILD","VM"],"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","target":"$TARGET","dependencies":{"layer4_services":"required"}}
EOFEOL
}
main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <target>"; exit 0; }
    [[ -z "$TARGET" ]] && error "Missing target"
    log "Building Layer 5: target=$TARGET"
    validate_config
    mkdir -p "$OUTPUT_DIR/settingsd"
    generate_dbus_config "$OUTPUT_DIR/settingsd"
    generate_evidence
    log "Layer 5 complete"
}
main "$@"
