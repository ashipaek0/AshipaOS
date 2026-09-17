#!/usr/bin/env bash
# Full Build Orchestration Script
# Runs all layers from 1-10 to produce complete bootable images
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAYERS_DIR="$ROOT_DIR/layers"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/output/work}"

export OUTPUT_DIR
export WORK_DIR

log() {
    echo "[full-build] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

die() {
    echo "[full-build] ERROR: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $(basename "$0") [OPTIONS] <target>"
    echo ""
    echo "Full AshipaOS Build - All Layers (1-10)"
    echo ""
    echo "Arguments:"
    echo "  target          Target device (x86_64, a95x-f3-air)"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  --skip-l1       Skip Layer 1 (use existing rootfs)"
    echo "  --rootfs PATH   Use existing rootfs tarball"
    echo "  --version VER   Set version string (default: YYYYMMDD)"
}

build_layer1() {
    local arch="$1"
    local output="$2"
    log "=== LAYER 1: Building RootFS (arch=$arch) ==="
    bash "$LAYERS_DIR/layer1-rootfs/scripts/build-rootfs.sh" "$arch" "$output"
    log "Layer 1 complete: $output"
}

build_layer2() {
    local rootfs="$1"
    local target="$2"
    log "=== LAYER 2: Building Disk Image (target=$target) ==="
    bash "$LAYERS_DIR/layer2-image/scripts/build-image.sh" "$rootfs" "$target"
    log "Layer 2 complete"
}

build_layer3() {
    local target="$1"
    log "=== LAYER 3: Configuring First-Boot Init (target=$target) ==="
    bash "$LAYERS_DIR/layer3-init/scripts/build-init.sh" "$target"
    log "Layer 3 complete"
}

build_layer4() {
    local target="$1"
    log "=== LAYER 4: Configuring System Services (target=$target) ==="
    bash "$LAYERS_DIR/layer4-services/scripts/build-services.sh" "$target"
    log "Layer 4 complete"
}

build_layer5() {
    local target="$1"
    log "=== LAYER 5: Building Settings Daemon (target=$target) ==="
    bash "$LAYERS_DIR/layer5-settingsd/scripts/build-settingsd.sh" "$target"
    log "Layer 5 complete"
}

build_layer6() {
    local target="$1"
    log "=== LAYER 6: Configuring OTA Mechanism (target=$target) ==="
    bash "$LAYERS_DIR/layer6-ota/scripts/build-ota.sh" "$target"
    log "Layer 6 complete"
}

build_layer7() {
    local target="$1"
    if [[ -f "$LAYERS_DIR/layer7-hal/scripts/build-7-hal.sh" ]]; then
        log "=== LAYER 7: Building HAL (target=$target) ==="
        bash "$LAYERS_DIR/layer7-hal/scripts/build-7-hal.sh" "$target"
        log "Layer 7 complete"
    else
        log "Layer 7 script not found, skipping"
    fi
}

build_layer8() {
    local target="$1"
    if [[ -f "$LAYERS_DIR/layer8-media/scripts/build-8-media.sh" ]]; then
        log "=== LAYER 8: Building Media Framework (target=$target) ==="
        bash "$LAYERS_DIR/layer8-media/scripts/build-8-media.sh" "$target"
        log "Layer 8 complete"
    else
        log "Layer 8 script not found, skipping"
    fi
}

build_layer9() {
    local target="$1"
    if [[ -f "$LAYERS_DIR/layer9-input/scripts/build-9-input.sh" ]]; then
        log "=== LAYER 9: Building Input Stack (target=$target) ==="
        bash "$LAYERS_DIR/layer9-input/scripts/build-9-input.sh" "$target"
        log "Layer 9 complete"
    else
        log "Layer 9 script not found, skipping"
    fi
}

build_layer10() {
    local target="$1"
    log "=== LAYER 10: Release Packaging (target=$target) ==="
    bash "$LAYERS_DIR/layer10-release/scripts/build-10-release.sh" "$target"
    log "Layer 10 complete"
}

generate_sbom() {
    log "=== Generating SBOM ==="
    bash "$ROOT_DIR/scripts/ci-generate-sbom.sh" "$OUTPUT_DIR/sbom.json"
    log "SBOM generated"
}

sign_artefacts() {
    log "=== Signing Artefacts ==="
    bash "$ROOT_DIR/scripts/ci-sign-artefacts.sh" "$OUTPUT_DIR/images" "$OUTPUT_DIR/ota"
    log "Signing complete"
}

main() {
    local skip_l1=false
    local existing_rootfs=""
    local version=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --skip-l1)
                skip_l1=true
                shift
                ;;
            --rootfs)
                existing_rootfs="$2"
                shift 2
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done
    
    local target="${1:-}"
    
    if [[ -z "$target" ]]; then
        die "Missing target argument. Use --help for usage."
    fi
    
    export VERSION="${version:-$(date +%Y%m%d)}"
    
    log "=========================================="
    log "AshipaOS Full Build"
    log "Target: $target"
    log "Version: $VERSION"
    log "Output: $OUTPUT_DIR"
    log "=========================================="
    
    mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
    
    local arch="amd64"
    case "$target" in
        x86_64) arch="amd64" ;;
        a95x-f3-air|arm64) arch="arm64" ;;
        *) log "WARNING: Unknown target $target, defaulting to amd64" ;;
    esac
    
    local rootfs_tar="$OUTPUT_DIR/rootfs-${target}.tar.gz"
    if [[ "$skip_l1" == "true" || -n "$existing_rootfs" ]]; then
        if [[ -n "$existing_rootfs" && -f "$existing_rootfs" ]]; then
            rootfs_tar="$existing_rootfs"
            log "Using existing rootfs: $rootfs_tar"
        elif [[ -f "$rootfs_tar" ]]; then
            log "Skipping Layer 1, using existing: $rootfs_tar"
        else
            die "Rootfs not found: $rootfs_tar"
        fi
    else
        build_layer1 "$arch" "$rootfs_tar"
    fi
    
    build_layer2 "$rootfs_tar" "$target"
    build_layer3 "$target"
    build_layer4 "$target"
    build_layer5 "$target"
    build_layer6 "$target"
    build_layer7 "$target"
    build_layer8 "$target"
    build_layer9 "$target"
    build_layer10 "$target"
    generate_sbom
    sign_artefacts
    
    log "=========================================="
    log "BUILD COMPLETE"
    log "=========================================="
    log "Artefacts:"
    log "  Images: $OUTPUT_DIR/images/"
    ls -la "$OUTPUT_DIR/images/" 2>/dev/null || true
    log "  OTA: $OUTPUT_DIR/ota/"
    ls -la "$OUTPUT_DIR/ota/" 2>/dev/null || true
    log "  SBOM: $OUTPUT_DIR/sbom.json"
    [[ -f "$OUTPUT_DIR/sbom.json" ]] && ls -la "$OUTPUT_DIR/sbom.json" || true
    
    echo ""
    echo "full-build: PASS"
}

main "$@"
