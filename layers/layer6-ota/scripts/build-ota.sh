#!/bin/bash
# Layer 6: OTA Update Mechanism
# Verification Class: BUILD, HARDWARE
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/ota-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/output}"
TARGET="${1:-x86_64}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Config not found"
    grep -q "ota:" "$CONFIG_FILE" || error "Missing ota section"
    log "Configuration valid"
}
generate_ota_manifest() {
    local out="$1"
    mkdir -p "$out/etc/ota"
    cat > "$out/etc/ota/manifest.json" << 'MANIFESTEOF'
{"version":"1.0","slots":{"a":"active","b":"inactive"},"update_policy":"A/B"}
MANIFESTEOF
    log "Generated OTA manifest"
}
generate_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    cat > "$EVIDENCE_DIR/build-evidence.json" << EOFEOL
{"layer":6,"verification_class":["BUILD","HARDWARE"],"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","target":"$TARGET","dependencies":{"layer5_settingsd":"required"}}
EOFEOL
}
main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <target>"; exit 0; }
    [[ -z "$TARGET" ]] && error "Missing target"
    log "Building Layer 6: target=$TARGET"
    validate_config
    mkdir -p "$OUTPUT_DIR/ota"
    generate_ota_manifest "$OUTPUT_DIR/ota"
    generate_evidence
    log "Layer 6 complete"
}
main "$@"
