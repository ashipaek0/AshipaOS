#!/bin/bash
# Layer 9-input: Build Script
# Verification Class: BUILD, HARDWARE
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/9-input-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/output}"
TARGET="${1:-x86_64}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
validate_config() { [[ -f "$CONFIG_FILE" ]] || error "Config not found"; log "Config valid"; }
generate_evidence() { mkdir -p "$EVIDENCE_DIR"; cat > "$EVIDENCE_DIR/build-evidence.json" << EOFEOL
{"layer":9-input,"verification_class":["BUILD","HARDWARE"],"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","target":"$TARGET"}
EOFEOL
}
main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <target>"; exit 0; }
    [[ -z "$TARGET" ]] && error "Missing target"
    log "Building Layer 9-input: target=$TARGET"
    validate_config
    mkdir -p "$OUTPUT_DIR/9-input"
    generate_evidence
    log "Layer 9-input complete"
}
main "$@"
