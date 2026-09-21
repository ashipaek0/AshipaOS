#!/bin/bash
# AshipaOS Build Environment Setup Script
# This script prepares your system for building AshipaOS images
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/rootfs-ownership.sh"

log() { echo "[SETUP] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
error() { echo "[SETUP ERROR] $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Setup build environment for AshipaOS image creation.

Options:
  -h, --help          Show this help message
  --install-deps      Install required system packages
  --generate-keys     Generate GPG signing keys
  --check-status      Check current environment status
  --setup-docker      Configure Docker for privileged builds
  --download-rootfs   Download pre-built Debian rootfs (skip Layer 1)
  --all               Run all setup steps

Environment Requirements:
  - debootstrap (Layer 1 rootfs creation)
  - qemu-user-static (cross-architecture builds)
  - parted, kpartx, dosfstools, e2fsprogs (Layer 2 image creation)
  - gzip, tar (compression)
  - GPG (artefact signing)

Examples:
  $(basename "$0") --install-deps --generate-keys
  $(basename "$0") --all
  $(basename "$0") --download-rootfs --check-status
EOF
    exit 0
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "WARNING: Not running as root. Some operations may require sudo."
        return 1
    fi
    return 0
}

# Install required dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    if command -v apt-get &>/dev/null; then
        log "Detected Debian/Ubuntu system"
        apt-get update
        apt-get install -y \
            debootstrap \
            qemu-user-static \
            qemu-utils \
            parted \
            kpartx \
            dosfstools \
            e2fsprogs \
            xz-utils \
            gzip \
            tar \
            gnupg \
            openssl \
            curl \
            ca-certificates
        
        log "Dependencies installed successfully"
        
    elif command -v dnf &>/dev/null; then
        log "Detected Fedora/RHEL system"
        dnf install -y \
            debootstrap \
            qemu-user-static \
            qemu-img \
            parted \
            dosfstools \
            e2fsprogs \
            xz \
            gzip \
            tar \
            gnupg2 \
            openssl \
            curl
            
        log "Dependencies installed successfully"
        
    else
        error "Unsupported package manager. Please install dependencies manually."
    fi
}

# Generate GPG signing keys
generate_gpg_keys() {
    log "Generating GPG signing keys..."
    
    local output_dir="$ROOT_DIR/output"
    mkdir -p "$output_dir"
    
    # Check if key already exists
    if gpg --list-secret-keys "AshipaOS Release Bot" &>/dev/null; then
        log "GPG key already exists. Skipping generation."
        echo ""
        echo "Existing key found:"
        gpg --list-secret-keys "AshipaOS Release Bot"
        echo ""
        echo "To export existing key:"
        echo "  gpg --armor --export-secret-keys 'AshipaOS Release Bot' > $output_dir/gpg_private_key.asc"
        return 0
    fi
    
    # Create temporary directory for key generation
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN
    
    # Generate key batch file
    cat > "$temp_dir/gpg_batch" <<EOF
%echo Generating AshipaOS Release Key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: AshipaOS Release Bot
Name-Email: release@ashipaos.local
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF
    
    log "Generating 4096-bit RSA key pair..."
    gpg --batch --gen-key "$temp_dir/gpg_batch" 2>/dev/null
    
    # Export private key
    log "Exporting private key..."
    gpg --armor --export-secret-keys "release@ashipaos.local" > "$output_dir/gpg_private_key.asc"
    
    # Generate passphrase (for documentation purposes, key has no protection)
    openssl rand -base64 32 > "$output_dir/gpg_passphrase.txt"
    
    # Export public key for verification
    gpg --armor --export "release@ashipaos.local" > "$output_dir/gpg_public_key.asc"
    
    log "✅ GPG keys generated successfully!"
    echo ""
    echo "Generated files:"
    echo "  - $output_dir/gpg_private_key.asc  (Add this to GitHub Secrets as GPG_PRIVATE_KEY)"
    echo "  - $output_dir/gpg_passphrase.txt   (Optional, add as GPG_PASSPHRASE)"
    echo "  - $output_dir/gpg_public_key.asc   (For verifying signatures)"
    echo ""
    echo "To add to GitHub:"
    echo "  1. Go to Repository Settings → Secrets and variables → Actions"
    echo "  2. Click 'New repository secret'"
    echo "  3. Name: GPG_PRIVATE_KEY, Value: Contents of gpg_private_key.asc"
    echo ""
}

# Check environment status
check_status() {
    log "Checking build environment status..."
    echo ""
    
    local all_ok=true
    
    # Check debootstrap
    if command -v debootstrap &>/dev/null; then
        echo "✓ debootstrap: $(debootstrap --version | head -1)"
    else
        echo "✗ debootstrap: NOT INSTALLED"
        all_ok=false
    fi
    
    # Check qemu-user-static
    if ls /usr/bin/qemu-*-static &>/dev/null 2>&1; then
        echo "✓ qemu-user-static: $(ls /usr/bin/qemu-*-static | wc -l) binaries available"
    else
        echo "✗ qemu-user-static: NOT INSTALLED"
        all_ok=false
    fi
    
    # Check image tools
    for tool in parted kpartx mkfs.vfat mkfs.ext4; do
        if command -v "$tool" &>/dev/null; then
            echo "✓ $tool: $(command -v "$tool")"
        else
            echo "✗ $tool: NOT INSTALLED"
            all_ok=false
        fi
    done
    
    # Check GPG
    if command -v gpg &>/dev/null; then
        echo "✓ GPG: $(gpg --version | head -1)"
        if gpg --list-secret-keys "AshipaOS Release Bot" &>/dev/null; then
            echo "  └─ Signing key: READY"
        else
            echo "  └─ Signing key: NOT GENERATED"
            all_ok=false
        fi
    else
        echo "✗ GPG: NOT INSTALLED"
        all_ok=false
    fi
    
    # Check loop device availability
    if [[ -e /dev/loop-control ]]; then
        echo "✓ Loop devices: AVAILABLE"
    else
        echo "⚠ Loop devices: NOT AVAILABLE (required for Layer 2 image creation)"
    fi
    
    # Check Docker (if available)
    if command -v docker &>/dev/null; then
        echo "✓ Docker: $(docker --version)"
        if docker info 2>/dev/null | grep -q "Security Options.*rootless"; then
            echo "  └─ Mode: Rootless (may need privileged mode for builds)"
        else
            echo "  └─ Mode: Standard"
        fi
    else
        echo "ℹ Docker: NOT INSTALLED (optional for containerized builds)"
    fi
    
    echo ""
    if [[ "$all_ok" == "true" ]]; then
        echo "✅ Environment is READY for building"
    else
        echo "⚠️  Some dependencies are missing. Run with --install-deps to fix."
    fi
    
    return 0
}

# Setup Docker for privileged builds
setup_docker() {
    log "Configuring Docker for privileged builds..."
    
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Create builder container configuration
    local docker_dir="$ROOT_DIR/ci/containers"
    mkdir -p "$docker_dir"
    
    cat > "$docker_dir/Dockerfile.builder" <<'EOF'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    debootstrap \
    qemu-user-static \
    qemu-utils \
    parted \
    kpartx \
    dosfstools \
    e2fsprogs \
    xz-utils \
    gzip \
    tar \
    gnupg \
    openssl \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Enable loop devices (requires privileged mode)
WORKDIR /workspace
VOLUME ["/workspace"]
EOF
    
    log "Docker builder configuration created at $docker_dir/Dockerfile.builder"
    echo ""
    echo "To build and run in Docker:"
    echo "  cd $docker_dir"
    echo "  docker build -f Dockerfile.builder -t ashipaos-builder ."
    echo "  docker run --privileged -v /workspace:/workspace ashipaos-builder"
    echo ""
    echo "Note: --privileged flag is required for loop device access"
}

# Download pre-built Debian rootfs
download_rootfs() {
    local arch="${1:-amd64}"
    local suite="${2:-bookworm}"
    
    log "Downloading pre-built Debian rootfs..."

    local output_dir="$ROOT_DIR/output"
    mkdir -p "$output_dir"

    log "Target architecture: $arch"
    log "Debian suite: $suite"
    
    local mirror="https://cloud.debian.org/images/cloud"
    
    # Map architecture to Debian cloud image names
    local deb_arch
    case "$arch" in
        amd64|x86_64) deb_arch="amd64" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac
    
    local latest_url="$mirror/$suite/latest/debian-${suite}-generic-${deb_arch}.qcow2"
    local tarball_url="$mirror/$suite/latest/debian-${suite}-genericcloud-${deb_arch}.tar.gz"
    
    log "Attempting to download from: $tarball_url"
    
    if curl --head --silent --fail "$tarball_url" &>/dev/null; then
        local output_file="$output_dir/rootfs-${deb_arch}.tar.gz"
        log "Downloading Debian cloud image..."
        curl -L -o "$output_file" "$tarball_url"
        
        log "Download complete: $output_file"
        log "Size: $(du -h "$output_file" | cut -f1)"
        
        # Verify it's a valid tarball
        if tar -tzf "$output_file" &>/dev/null; then
            rootfs_output_owner "$output_file" "$output_dir" \
                || error "Could not restore rootfs output ownership"
            log "✓ Tarball validation successful"
            echo ""
            echo "Rootfs ready for Layer 2 build!"
            echo "Use with: ./build/scripts/full-build.sh --skip-l1 --rootfs $output_file <target>"
        else
            error "Downloaded file is not a valid tarball"
        fi
    else
        log "Cloud image not available, trying alternative source..."
        
        # Fallback: Create minimal rootfs using debootstrap if available
        if command -v debootstrap &>/dev/null; then
            log "Falling back to debootstrap..."
            local temp_dir
            temp_dir=$(mktemp -d)
            trap "rm -rf '$temp_dir'" RETURN
            
            debootstrap --arch="$deb_arch" "$suite" "$temp_dir/rootfs" "http://deb.debian.org/debian"
            
            # Minimize
            find "$temp_dir/rootfs/usr/share/doc" -type f ! -name 'copyright' -delete 2>/dev/null || true
            rm -rf "$temp_dir/rootfs/var/cache/apt/archives"/*
            rm -rf "$temp_dir/rootfs/tmp"/* "$temp_dir/rootfs/var/tmp"/*
            find "$temp_dir/rootfs/var/log" -type f -delete 2>/dev/null || true
            
            tar -C "$temp_dir/rootfs" \
                --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*' \
                -czf "$output_dir/rootfs-${deb_arch}.tar.gz" .
            rootfs_output_owner "$output_dir/rootfs-${deb_arch}.tar.gz" "$output_dir" \
                || error "Could not restore rootfs output ownership"
            log "Rootfs created via debootstrap: $output_dir/rootfs-${deb_arch}.tar.gz"
        else
            error "Cannot create rootfs: debootstrap not available and cloud image download failed"
        fi
    fi
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi
    
    local do_install_deps=false
    local do_generate_keys=false
    local do_check_status=false
    local do_setup_docker=false
    local do_download_rootfs=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            --install-deps)
                do_install_deps=true
                shift
                ;;
            --generate-keys)
                do_generate_keys=true
                shift
                ;;
            --check-status)
                do_check_status=true
                shift
                ;;
            --setup-docker)
                do_setup_docker=true
                shift
                ;;
            --download-rootfs)
                do_download_rootfs=true
                shift
                ;;
            --all)
                do_install_deps=true
                do_generate_keys=true
                do_setup_docker=true
                do_download_rootfs=true
                do_check_status=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    log "=========================================="
    log "AshipaOS Build Environment Setup"
    log "=========================================="
    echo ""
    
    if [[ "$do_check_status" == "true" ]]; then
        check_status
        echo ""
    fi
    
    if [[ "$do_install_deps" == "true" ]]; then
        if check_root; then
            install_dependencies
        else
            log "Please run with sudo or as root to install dependencies"
            echo "Or run: sudo $0 --install-deps"
            echo ""
        fi
    fi
    
    if [[ "$do_generate_keys" == "true" ]]; then
        generate_gpg_keys
        echo ""
    fi
    
    if [[ "$do_setup_docker" == "true" ]]; then
        setup_docker
        echo ""
    fi
    
    if [[ "$do_download_rootfs" == "true" ]]; then
        download_rootfs
        echo ""
    fi
    
    log "=========================================="
    log "Setup Complete!"
    log "=========================================="
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "1. If you generated GPG keys, add them to GitHub Secrets:"
    echo "   - Repository Settings → Secrets and variables → Actions"
    echo "   - Add GPG_PRIVATE_KEY from output/gpg_private_key.asc"
    echo ""
    echo "2. For full builds with loop devices:"
    echo "   - Use GitHub Actions with privileged containers, OR"
    echo "   - Use self-hosted runners with loop device access, OR"
    echo "   - Run locally with sudo"
    echo ""
    echo "3. To build images:"
    echo "   ./build/scripts/full-build.sh x86_64"
    echo ""
    echo "4. To skip Layer 1 and use downloaded rootfs:"
    echo "   ./build/scripts/full-build.sh --skip-l1 x86_64"
    echo ""
}

main "$@"
