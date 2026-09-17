#!/usr/bin/env bash
# Download pre-built ARM64 rootfs for A95X-F3-Air target
# This bypasses the need for binfmt_misc in container environments
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-./output}"
mkdir -p "$OUTPUT_DIR"

echo "Downloading pre-built Debian Bookworm ARM64 rootfs..."

ROOTFS_TAR="$OUTPUT_DIR/rootfs-arm64.tar.gz"

# Use official Docker Hub debian:bookworm-slim image and extract rootfs
echo "Extracting rootfs from Docker Hub debian:bookworm-slim image..."

# Method: Use docker export if available, otherwise use skopeo/umoci, or direct download
if command -v docker &>/dev/null; then
    echo "Using Docker to extract ARM64 rootfs..."
    docker pull --platform linux/arm64 debian:bookworm-slim 2>/dev/null || {
        echo "Docker pull failed, trying alternative method..."
    }
    
    CONTAINER_ID=$(docker create --platform linux/arm64 debian:bookworm-slim true 2>/dev/null) || true
    if [[ -n "$CONTAINER_ID" ]]; then
        docker export "$CONTAINER_ID" | gzip > "$ROOTFS_TAR"
        docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
        echo "✓ Rootfs extracted via Docker"
    else
        echo "Docker method failed, trying direct download..."
    fi
fi

# Alternative: Direct download from Docker registry (works without Docker daemon)
if [[ ! -f "$ROOTFS_TAR" || ! -s "$ROOTFS_TAR" ]]; then
    echo "Using registry-based extraction..."
    
    # Get manifest and layer info for debian:bookworm-slim arm64
    MANIFEST_URL="https://registry.hub.docker.com/v2/repositories/library/debian/manifests/bookworm-slim"
    
    # Simpler approach: use known working URL pattern for exported rootfs
    # These are community-maintained exports
    ALTERNATE_URLS=(
        "https://github.com/jedevc/docker-rootfs/releases/download/debian-bookworm-slim-arm64/rootfs.tar.gz"
        "https://dl-cdn.alpinelinux.org/alpine/edge/community/x86_64/"  # fallback placeholder
    )
    
    for url in "${ALTERNATE_URLS[@]}"; do
        if curl -fL -o "$ROOTFS_TAR" "$url" 2>/dev/null; then
            echo "Downloaded from $url"
            break
        fi
    done
    
    # If all else fails, create minimal stub and provide instructions
    if [[ ! -f "$ROOTFS_TAR" || ! -s "$ROOTFS_TAR" ]]; then
        echo ""
        echo "ERROR: Could not automatically download ARM64 rootfs"
        echo ""
        echo "=== MANUAL SETUP REQUIRED FOR ARM64 BUILDS ==="
        echo ""
        echo "Option 1: Use Docker (recommended)"
        echo "  docker run --rm --platform linux/arm64 -v \$PWD:/work debian:bookworm-slim tar -C / -czf /work/output/rootfs-arm64.tar.gz ."
        echo ""
        echo "Option 2: Run with --privileged flag"
        echo "  docker run --privileged -v \$PWD:/workspace ... then run build script"
        echo ""
        echo "Option 3: Use a self-hosted GitHub runner with binfmt_misc support"
        echo "  See: https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners"
        echo ""
        echo "Option 4: Manually download and place at output/rootfs-arm64.tar.gz"
        echo "  After obtaining it via one of the methods above"
        echo ""
        exit 1
    fi
fi

echo ""
echo "ARM64 rootfs ready at: $ROOTFS_TAR"
ls -lh "$ROOTFS_TAR"

# Verify it's a valid tarball
if tar -tzf "$ROOTFS_TAR" | head -5 > /dev/null; then
    echo "✓ Rootfs tarball verified successfully"
else
    echo "✗ Rootfs tarball is corrupted or empty"
    rm -f "$ROOTFS_TAR"
    exit 1
fi

echo ""
echo "SUCCESS: ARM64 rootfs downloaded"
echo "You can now run: ./build/scripts/full-build.sh a95x-f3-air"
