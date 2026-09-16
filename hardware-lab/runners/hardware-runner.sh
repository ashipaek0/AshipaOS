#!/usr/bin/env bash
# Layer 0: Hardware lab inventory stub
# Per build guide §0.9 and §1.5: hardware facts require evidence
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARDWARE_LAB_DIR="$ROOT_DIR/hardware-lab"
INVENTORY_FILE="$HARDWARE_LAB_DIR/inventory.yaml"

log() {
    echo "[hardware-lab] $*"
}

die() {
    echo "[hardware-lab] ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] COMMAND

AshipaOS Hardware Lab Runner (Layer 0)

Commands:
  init          Initialize hardware lab structure
  status        Show hardware lab status
  list-devices  List registered hardware devices
  help          Show this help message

Options:
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

Examples:
  $(basename "$0") init
  $(basename "$0") status
  $(basename "$0") list-devices

EOF
}

cmd_init() {
    log "Initializing hardware lab structure..."
    
    mkdir -p "$HARDWARE_LAB_DIR/runners"
    mkdir -p "$HARDWARE_LAB_DIR/power"
    mkdir -p "$HARDWARE_LAB_DIR/serial"
    mkdir -p "$HARDWARE_LAB_DIR/flashing"
    mkdir -p "$HARDWARE_LAB_DIR/tests"
    mkdir -p "$ROOT_DIR/evidence/amlogic"
    mkdir -p "$ROOT_DIR/evidence/x86_64"
    
    # Create inventory file if it doesn't exist
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        cat > "$INVENTORY_FILE" <<'YAML'
# Hardware Lab Inventory (Layer 0 stub)
# Per build guide §0.9: remote hardware lab for automated testing
# Status: PROVISIONAL until physical devices are registered with evidence

devices:
  x86_64-generic:
    type: x86_64-pc
    status: UNKNOWN
    evidence: []
    capabilities:
      serial_console: UNKNOWN
      network_power: UNKNOWN
      boot_media: UNKNOWN
    
  a95x-f3-air:
    type: amlogic-s905x3-box
    status: UNKNOWN
    evidence: []
    capabilities:
      serial_console: UNKNOWN
      network_power: UNKNOWN
      boot_media: UNKNOWN

lab_status:
  automation_ready: false
  remote_access: false
  evidence_collection: MANUAL

notes: |
  Layer 0: Hardware lab structure initialized.
  Physical device registration and evidence collection pending.
  All device statuses are UNKNOWN until verified with recorded evidence.
YAML
        log "Created inventory file: $INVENTORY_FILE"
    else
        log "Inventory file already exists: $INVENTORY_FILE"
    fi
    
    echo "hardware-lab-init: PASS"
}

cmd_status() {
    log "Hardware Lab Status (Layer 0)"
    echo ""
    
    if [[ -f "$INVENTORY_FILE" ]]; then
        log "Inventory file: PRESENT"
        log "Devices registered: $(grep -c '^  [a-z]' "$INVENTORY_FILE" 2>/dev/null || echo "0")"
    else
        log "Inventory file: MISSING (run 'init' first)"
    fi
    
    echo ""
    log "Lab capabilities:"
    echo "  - Automation ready: NO (Layer 0 stub)"
    echo "  - Remote access: NO (requires physical setup)"
    echo "  - Evidence collection: MANUAL only"
    echo ""
    log "Per build guide §0.9: Hardware tests require physical devices."
    log "GitHub CI can prove software correctness, not hardware behaviour."
    
    echo ""
    echo "status: PASS"
}

cmd_list_devices() {
    log "Registered hardware devices:"
    echo ""
    
    if [[ -f "$INVENTORY_FILE" ]]; then
        # Extract device names from inventory
        grep -E '^  [a-z].*:$' "$INVENTORY_FILE" | sed 's/:$//' | while read -r device; do
            echo "  - $device"
        done
    else
        echo "  (no devices registered - run 'init' first)"
    fi
    
    echo ""
    echo "list-devices: PASS"
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        init)
            cmd_init "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        list-devices)
            cmd_list_devices "$@"
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown command: $command"
            ;;
    esac
}

main "$@"
