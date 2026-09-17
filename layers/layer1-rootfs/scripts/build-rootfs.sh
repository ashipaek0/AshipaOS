#!/bin/bash
# Layer 1: Minimal Debian Root Filesystem Builder
# Verification Class: BUILD (requires debootstrap)
# 
# This script creates a minimal Debian rootfs for target architectures.
# It is designed to run in the canonical builder environment (GitHub Actions).

set -euo pipefail

# Auto-elevate to root if not already running as root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER1_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$(dirname "$LAYER1_DIR")"

# Configuration
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
COMPONENTS="${COMPONENTS:-main,contrib,non-free-firmware}"

# Architecture mapping
declare -A ARCH_MAP=(
    ["arm64"]="arm64"
    ["amd64"]="amd64"
    ["armhf"]="armhf"
)

usage() {
    cat <<EOF
Usage: $(basename "$0") <target_arch> <output_dir>

Creates a minimal Debian root filesystem for the specified architecture.

Arguments:
  target_arch   Target architecture (arm64, amd64, armhf)
  output_dir    Output directory for the rootfs tarball

Environment Variables:
  DEBIAN_SUITE      Debian suite (default: bookworm)
  DEBIAN_MIRROR     Debian mirror URL (default: http://deb.debian.org/debian)
  COMPONENTS        Debian components (default: main,contrib,non-free-firmware)

Example:
  $(basename "$0") arm64 /workspace/output/rootfs-arm64.tar.gz
EOF
    exit 1
}

log() {
    echo "[L1-ROOTFS] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

error() {
    echo "[L1-ROOTFS ERROR] $*" >&2
    exit 1
}

# Validate dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    local target_arch="$1"
    
    if ! command -v debootstrap &>/dev/null; then
        missing_deps+=("debootstrap")
    fi
    
    # Only required for cross-architecture builds
    if [[ "$target_arch" != "$(dpkg --print-architecture)" ]]; then
        # Check for any qemu-user-static binary (qemu-aarch64-static, qemu-arm-static, etc.)
        if ! ls /usr/bin/qemu-*-static &>/dev/null; then
            missing_deps+=("qemu-user-static")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing_deps[*]}"
    fi
    
    log "Dependencies OK"
}

# Create minimal rootfs
create_rootfs() {
    local target_arch="$1"
    local output_dir="$2"
    local temp_dir
    
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT
    
    log "Creating temporary directory: $temp_dir"
    log "Building Debian $DEBIAN_SUITE rootfs for $target_arch"
    
    # Run debootstrap
    if [[ "$target_arch" != "$(dpkg --print-architecture)" ]]; then
        log "Cross-architecture build detected, using qemu-user-static"
        debootstrap --arch="$target_arch" \
                    --components="$COMPONENTS" \
                    --foreign \
                    "$DEBIAN_SUITE" \
                    "$temp_dir/rootfs" \
                    "$DEBIAN_MIRROR"
        
        # Copy qemu-user-static for second stage
        # Map architecture names to qemu binary names
        local qemu_arch
        case "$target_arch" in
            arm64) qemu_arch="aarch64" ;;
            armhf) qemu_arch="arm" ;;
            amd64) qemu_arch="x86_64" ;;
            *) qemu_arch="$target_arch" ;;
        esac
        
        cp "/usr/bin/qemu-${qemu_arch}-static" "$temp_dir/rootfs/usr/bin/"
        
        # Second stage
        chroot "$temp_dir/rootfs" /debootstrap/debootstrap --second-stage
        
        # Cleanup qemu binary
        rm -f "$temp_dir/rootfs/usr/bin/qemu-${qemu_arch}-static"
    else
        debootstrap --arch="$target_arch" \
                    --components="$COMPONENTS" \
                    "$DEBIAN_SUITE" \
                    "$temp_dir/rootfs" \
                    "$DEBIAN_MIRROR"
    fi
    
    # Minimize the rootfs
    log "Minimizing rootfs..."
    minimize_rootfs "$temp_dir/rootfs"
    
    # Create tarball
    mkdir -p "$(dirname "$output_dir")"
    log "Creating rootfs tarball: $output_dir"
    tar -C "$temp_dir/rootfs" -czf "$output_dir" .
    
    log "Rootfs created successfully: $output_dir"
    log "Size: $(du -h "$output_dir" | cut -f1)"
}

# Minimize rootfs by removing unnecessary files
minimize_rootfs() {
    local rootfs_dir="$1"
    
    log "Removing unnecessary files from rootfs..."
    
    # Remove documentation
    find "$rootfs_dir"/usr/share/doc -type f ! -name 'copyright' -delete || true
    find "$rootfs_dir"/usr/share/man -type f -delete || true
    find "$rootfs_dir"/usr/share/info -type f -delete || true
    
    # Remove apt cache
    rm -rf "$rootfs_dir"/var/cache/apt/archives/*
    
    # Remove temporary files
    rm -rf "$rootfs_dir"/tmp/*
    rm -rf "$rootfs_dir"/var/tmp/*
    
    # Remove log files
    find "$rootfs_dir"/var/log -type f -delete || true
    
    log "Rootfs minimized"
}

# Generate evidence
generate_evidence() {
    local target_arch="$1"
    local output_dir="$2"
    local evidence_dir="$LAYER1_DIR/evidence"
    
    mkdir -p "$evidence_dir"
    
    cat > "$evidence_dir/build-evidence-$(date +%Y%m%d-%H%M%S).json" <<EOF
{
    "layer": 1,
    "task": "minimal-debian-rootfs",
    "verification_class": "BUILD",
    "timestamp": "$(date -Iseconds)",
    "parameters": {
        "debian_suite": "$DEBIAN_SUITE",
        "debian_mirror": "$DEBIAN_MIRROR",
        "components": "$COMPONENTS",
        "target_arch": "$target_arch"
    },
    "artefacts": {
        "rootfs_tarball": "$output_dir",
        "rootfs_size": "$(du -b "$output_dir" 2>/dev/null | cut -f1 || echo 'unknown')"
    },
    "builder": {
        "hostname": "$(hostname)",
        "architecture": "$(dpkg --print-architecture)",
        "debootstrap_version": "$(dpkg -l debootstrap 2>/dev/null | grep debootstrap | awk '{print $3}' || echo 'unknown')"
    }
}
EOF
    
    log "Evidence generated in $evidence_dir"
}

# Main execution
main() {
    if [[ $# -lt 2 ]]; then
        usage
    fi
    
    local target_arch="$1"
    local output_dir="$2"
    
    # Validate architecture
    if [[ -z "${ARCH_MAP[$target_arch]:-}" ]]; then
        error "Invalid architecture: $target_arch. Valid options: ${!ARCH_MAP[*]}"
    fi
    
    log "Starting Layer 1 rootfs build"
    log "Target architecture: $target_arch"
    log "Output: $output_dir"
    
    check_dependencies "$target_arch"
    
    create_rootfs "$target_arch" "$output_dir"
    generate_evidence "$target_arch" "$output_dir"
    
    log "Layer 1 build completed successfully"
}

main "$@"
