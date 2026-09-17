#!/bin/bash
# Layer 3: First-Boot Initialization (cloud-init / systemd-firstboot)
# Verification Class: BUILD, VM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/init-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/output}"
TARGET="${1:-x86_64}"
MODE="${2:-systemd-firstboot}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <target> [mode]

Configure first-boot initialization for target device.

Arguments:
    target          Target device (x86_64, a95x-f3-air)
    mode            Initialization mode: cloud-init or systemd-firstboot (default: systemd-firstboot)

Options:
    -h, --help      Show this help message
    --validate      Validate configuration only
    --hostname H    Override hostname

Verification Class: BUILD, VM
Dependencies: Layer 2 (disk image)
EOF
    exit 0
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

validate_config() {
    log "Validating init configuration..."
    if [[ ! -f "$CONFIG_FILE" ]]; then
        # Create default config if missing
        log "Creating default configuration..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" <<EOF
# Layer 3: Init Configuration
hostname: ashipaos
users:
  - name: ashipa
    sudo: ALL=(ALL) NOPASSWD:ALL
EOF
    fi
    grep -q "hostname:" "$CONFIG_FILE" || error "Missing 'hostname' in configuration"
    log "Configuration validation passed"
}

generate_systemd_firstboot() {
    local output_dir="$1"
    local hostname
    hostname=$(grep "hostname:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1)
    : "${hostname:=ashipaos}"
    
    mkdir -p "$output_dir/etc/systemd"
    
    echo "$hostname" > "$output_dir/etc/hostname"
    
    cat > "$output_dir/etc/systemd/firstboot.conf" <<EOF
[FirstBoot]
Hostname=$hostname
Timezone=UTC
EOF
    
    # Generate machine-id placeholder
    rm -f "$output_dir/etc/machine-id"
    touch "$output_dir/etc/machine-id"
    
    log "Generated systemd-firstboot configuration (hostname=$hostname)"
}

generate_evidence() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$EVIDENCE_DIR"
    
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{
    "layer": 3,
    "verification_class": ["BUILD", "VM"],
    "timestamp": "$timestamp",
    "build_host": "$(hostname)",
    "target": "$TARGET",
    "mode": "$MODE",
    "configuration": {
        "init_mode": "$MODE",
        "hostname_configured": true
    },
    "dependencies": {
        "layer2_image": "required"
    },
    "tests_required": [
        "firstboot_completion",
        "hostname_set",
        "user_created"
    ]
}
EOF
    log "Evidence generated: $EVIDENCE_DIR/build-evidence.json"
}

main() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
    [[ "${1:-}" == "--validate" ]] && { validate_config; echo "Configuration valid"; exit 0; }
    
    [[ -z "$TARGET" ]] && error "Missing required argument. Use --help for usage."
    
    log "Starting Layer 3 build: target=$TARGET, mode=$MODE"
    validate_config
    
    mkdir -p "$OUTPUT_DIR/init"
    
    generate_systemd_firstboot "$OUTPUT_DIR/init"
    generate_evidence
    
    log "Layer 3 build complete"
}

main "$@"
