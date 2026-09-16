#!/usr/bin/env bash
# Layer 0: Canonical build orchestration script
# Per build guide §1.3: shell standard compliance
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
OUTPUT_DIR="$BUILD_DIR/output"
WORK_DIR="$BUILD_DIR/work"
CONFIG_DIR="$BUILD_DIR/config"
TARGETS_DIR="$BUILD_DIR/targets"

log() {
    echo "[build] $*"
}

die() {
    echo "[build] ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] COMMAND

AshipaOS Build Orchestrator (Layer 0)

Commands:
  init          Initialize build directories
  list-targets  List available build targets
  validate      Validate target configurations
  help          Show this help message

Options:
  -t, --target TARGET   Specify target (for future use)
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

Examples:
  $(basename "$0") init
  $(basename "$0") list-targets
  $(basename "$0") validate

EOF
}

cmd_init() {
    log "Initializing build directories..."
    
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$BUILD_DIR/rootfs"
    mkdir -p "$BUILD_DIR/scripts"
    
    log "Build directories initialized:"
    log "  Output: $OUTPUT_DIR"
    log "  Work:   $WORK_DIR"
    log "  Rootfs: $BUILD_DIR/rootfs"
    
    echo "build-init: PASS"
}

cmd_list_targets() {
    log "Available targets:"
    
    for yaml_file in "$TARGETS_DIR"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            target_name="$(basename "$yaml_file" .yaml)"
            echo "  - $target_name"
        fi
    done
    
    if [[ -d "$TARGETS_DIR/amlogic/boxes" ]]; then
        log "Amlogic boxes:"
        for yaml_file in "$TARGETS_DIR/amlogic/boxes"/*.yaml; do
            if [[ -f "$yaml_file" ]]; then
                box_name="$(basename "$yaml_file" .yaml)"
                echo "  - $box_name"
            fi
        done
    fi
    
    echo "list-targets: PASS"
}

cmd_validate() {
    log "Validating target configurations..."
    
    local fail=0
    
    # Validate release.yaml exists
    if [[ ! -f "$CONFIG_DIR/release.yaml" ]]; then
        die "Missing release.yaml"
    fi
    log "✓ release.yaml present"
    
    # Validate packages.lock exists
    if [[ ! -f "$CONFIG_DIR/packages.lock" ]]; then
        die "Missing packages.lock"
    fi
    log "✓ packages.lock present"
    
    # Validate target files exist
    local target_count=0
    for yaml_file in "$TARGETS_DIR"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            ((target_count++)) || true
            log "✓ Target: $(basename "$yaml_file")"
        fi
    done
    
    if [[ $target_count -eq 0 ]]; then
        die "No target files found"
    fi
    
    # Validate Amlogic platform if it exists
    if [[ -d "$TARGETS_DIR/amlogic" ]]; then
        log "✓ Amlogic target directory present"
        
        # Check for box configurations
        if [[ -d "$TARGETS_DIR/amlogic/boxes" ]]; then
            local box_count=0
            for yaml_file in "$TARGETS_DIR/amlogic/boxes"/*.yaml; do
                if [[ -f "$yaml_file" ]]; then
                    ((box_count++)) || true
                    log "✓ Box: $(basename "$yaml_file")"
                fi
            done
            
            if [[ $box_count -eq 0 ]]; then
                log "WARNING: No box configurations found"
            fi
        fi
    fi
    
    # Validate schemas exist
    if [[ ! -d "$ROOT_DIR/schemas" ]]; then
        die "Missing schemas directory"
    fi
    log "✓ Schemas directory present"
    
    if [[ $fail -ne 0 ]]; then
        echo "validate: FAIL"
        exit 1
    fi
    
    echo "validate: PASS"
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
        list-targets)
            cmd_list_targets "$@"
            ;;
        validate)
            cmd_validate "$@"
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
