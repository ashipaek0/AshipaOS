#!/bin/bash
# Layer 4: Core System Services (systemd units)
# Verification Class: BUILD, VM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/services-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/output}"
TARGET="${1:-x86_64}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <target>

Assemble core systemd services for target device.

Arguments:
    target          Target device (x86_64, a95x-f3-air)

Options:
    -h, --help      Show this help message
    --validate      Validate configuration only
    --list          List available services

Verification Class: BUILD, VM
Dependencies: Layer 3 (init)
EOF
    exit 0
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

validate_config() {
    log "Validating services configuration..."
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found: $CONFIG_FILE"
    grep -q "services:" "$CONFIG_FILE" || error "Missing 'services' section"
    grep -q "enabled:" "$CONFIG_FILE" || error "Missing 'enabled' list"
    log "Configuration validation passed"
}

list_services() {
    log "Available services:"
    grep -A20 "^enabled:" "$CONFIG_FILE" | grep "^  -" | sed 's/^  - /  ✓ /'
}

generate_service_bundle() {
    local output_dir="$1"
    mkdir -p "$output_dir/etc/systemd/system"
    mkdir -p "$output_dir/etc/systemd/presets"
    
    # Generate preset file
    cat > "$output_dir/etc/systemd/presets/ashipaos.preset" <<EOF
# AshipaOS Service Presets
$(grep -A20 "^enabled:" "$CONFIG_FILE" | grep "^  -" | sed 's/^  - /enable /')
disable *
EOF
    
    # Create service stub files for critical services
    local services=("ssh" "networking" "systemd-journald" "systemd-logind" "cron" "dbus")
    for svc in "${services[@]}"; do
        if grep -q "$svc" "$CONFIG_FILE"; then
            cat > "$output_dir/etc/systemd/system/${svc}.service.stub" <<EOF
[Unit]
Description=$svc service stub
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
        fi
    done
    
    log "Generated service bundle with presets"
}

generate_evidence() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p "$EVIDENCE_DIR"
    
    local enabled_count
    enabled_count=$(grep -A20 "^enabled:" "$CONFIG_FILE" | grep -c "^  -" || echo "0")
    
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{
    "layer": 4,
    "verification_class": ["BUILD", "VM"],
    "timestamp": "$timestamp",
    "build_host": "$(hostname)",
    "target": "$TARGET",
    "configuration": {
        "enabled_services_count": $enabled_count,
        "preset_file_generated": true
    },
    "dependencies": {
        "layer3_init": "required"
    },
    "tests_required": [
        "systemd_analyze_verify",
        "preset_validation",
        "service_startup_test"
    ]
}
EOF
    log "Evidence generated: $EVIDENCE_DIR/build-evidence.json"
}

main() {
    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
    [[ "${1:-}" == "--validate" ]] && { validate_config; echo "Configuration valid"; exit 0; }
    [[ "${1:-}" == "--list" ]] && { list_services; exit 0; }
    
    [[ -z "$TARGET" ]] && error "Missing required argument. Use --help for usage."
    
    log "Starting Layer 4 build: target=$TARGET"
    validate_config
    
    mkdir -p "$OUTPUT_DIR/services"
    generate_service_bundle "$OUTPUT_DIR/services"
    generate_evidence
    
    log "Layer 4 build complete"
}

main "$@"
