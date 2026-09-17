#!/usr/bin/env bash
# Layer 10-release: Build Script - Final Release Packaging
# Verification Class: BUILD, HARDWARE
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../../.." && pwd)"
CONFIG_FILE="$LAYER_DIR/config/10-release-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${OUTPUT_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output}"
IMAGES_DIR="$OUTPUT_DIR/images"
OTA_DIR="$OUTPUT_DIR/ota"
TARGET="${1:-x86_64}"
VERSION="${VERSION:-$(date +%Y%m%d)}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
validate_config() { [[ -f "$CONFIG_FILE" ]] || error "Config not found"; log "Config valid"; }

package_release() {
    local target="$1"
    local version="$2"
    
    log "Packaging release for $target version $version"
    
    # Create output directories
    mkdir -p "$IMAGES_DIR" "$OTA_DIR"
    
    # Find and compress disk images from Layer 2
    local img_found=false
    local image_checksums="$IMAGES_DIR/SHA256SUMS-$target"
    local ota_checksums="$OTA_DIR/SHA256SUMS-$target"
    rm -f "$image_checksums" "$ota_checksums"
    for img in "$IMAGES_DIR"/ashipaos-"$target"-*.img; do
        if [[ -f "$img" ]]; then
            img_found=true
            local basename_img
            basename_img=$(basename "$img" .img)
            local compressed_img="$IMAGES_DIR/${basename_img}.img.gz"
            
            log "Compressing image: $img -> $compressed_img"
            gzip -c "$img" > "$compressed_img"
            
            # Calculate SHA256
            local sha256
            sha256=$(sha256sum "$compressed_img" | awk '{print $1}')
            echo "$sha256  $(basename "$compressed_img")" >> "$image_checksums"
            
            # Create OTA package from the image
            local ota_pkg="$OTA_DIR/${basename_img}-${version}.pkg"
            log "Creating OTA package: $ota_pkg"
            
            # OTA package format: metadata + payload
            cat > "${ota_pkg}.meta.json" <<EOF
{
    "package_type": "full_image",
    "target": "$target",
    "version": "$version",
    "payload": "$(basename "$compressed_img")",
    "sha256": "$sha256",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
            # Bundle into tarball
            tar -czf "$ota_pkg" -C "$IMAGES_DIR" "$(basename "$compressed_img")" -C "$(dirname "$ota_pkg")" "$(basename "${ota_pkg}.meta.json")"
            rm -f "${ota_pkg}.meta.json"
            
            local ota_sha256
            ota_sha256=$(sha256sum "$ota_pkg" | awk '{print $1}')
            echo "$ota_sha256  $(basename "$ota_pkg")" >> "$ota_checksums"
            
            log "Created OTA package with SHA256: $ota_sha256"
        fi
    done
    
    [[ "$img_found" == true ]] || error "No Layer 2 .img files found in $IMAGES_DIR"
    
    log "Release packaging complete"
    log "Images directory: $IMAGES_DIR"
    log "OTA directory: $OTA_DIR"
    ls -la "$IMAGES_DIR"
    ls -la "$OTA_DIR"
}

generate_evidence() { 
    local runner=human run_id=local job_id=local commit_sha
    [[ "${GITHUB_ACTIONS:-false}" == true ]] && runner=github-actions
    run_id="${GITHUB_RUN_ID:-$run_id}"
    job_id="${GITHUB_JOB:-$job_id}"
    commit_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    mkdir -p "$EVIDENCE_DIR"
    cat > "$EVIDENCE_DIR/build-evidence.json" << EOFEOL
{"layer":10,"task_id":"layer10-release-packaging","verification_class":"BUILD","runner":"$runner","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","target":"$TARGET","result":"PASS","evidence_path":"$EVIDENCE_DIR/build-evidence.json","commit_sha":"$commit_sha","ci_run_id":"$run_id","ci_job_id":"$job_id","artefacts":{"images_dir":"$IMAGES_DIR","ota_dir":"$OTA_DIR"},"blocked_gates":["VM","HARDWARE"]}
EOFEOL
}

main() {
    [[ "${1:-}" == "-h" ]] && { echo "Usage: $0 <target> [version]"; exit 0; }
    [[ -z "$TARGET" ]] && error "Missing target"
    
    log "Building Layer 10-release: target=$TARGET, version=$VERSION"
    validate_config
    package_release "$TARGET" "$VERSION"
    generate_evidence
    log "Layer 10-release complete"
}
main "$@"
