#!/bin/bash
# CI Script: Sign Artefacts with GPG
# Usage: ci-sign-artefacts.sh <images_dir> <ota_dir>

set -euo pipefail

IMAGES_DIR="${1:-output/images}"
OTA_DIR="${2:-output/ota}"

echo "=== Signing Artefacts ==="

# Check if GPG key is available (skip in dev mode)
if ! gpg --list-secret-keys 2>/dev/null | grep -q "AshipaOS Release"; then
    echo "WARNING: GPG private key not found. Skipping signing (development mode)."
    echo "To enable signing, set GPG_PRIVATE_KEY and GPG_PASSPHRASE secrets."
    
    # Create placeholder signature files for testing
    if [ -d "$IMAGES_DIR" ]; then
        for img in "$IMAGES_DIR"/*.img.gz; do
            if [ -f "$img" ]; then
                echo "PLACEHOLDER_SIGNATURE" > "${img}.sig"
                echo "  Created placeholder: $(basename "${img}.sig")"
            fi
        done
    fi
    
    if [ -d "$OTA_DIR" ]; then
        for pkg in "$OTA_DIR"/*.pkg; do
            if [ -f "$pkg" ]; then
                echo "PLACEHOLDER_SIGNATURE" > "${pkg}.sig"
                echo "  Created placeholder: $(basename "${pkg}.sig")"
            fi
        done
    fi
    
    if [ -f "output/sbom.json" ]; then
        echo "PLACEHOLDER_SIGNATURE" > "output/sbom.json.sig"
        echo "  Created placeholder: sbom.json.sig"
    fi
    
    exit 0
fi

# Production signing mode
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

# Sign disk images
if [ -d "$IMAGES_DIR" ]; then
    echo "Signing disk images in $IMAGES_DIR..."
    for img in "$IMAGES_DIR"/*.img.gz; do
        if [ -f "$img" ]; then
            echo "  Signing: $(basename "$img")"
            echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
                --armor --detach-sign "$img"
        fi
    done
else
    echo "WARNING: Images directory not found: $IMAGES_DIR"
fi

# Sign OTA packages
if [ -d "$OTA_DIR" ]; then
    echo "Signing OTA packages in $OTA_DIR..."
    for pkg in "$OTA_DIR"/*.pkg; do
        if [ -f "$pkg" ]; then
            echo "  Signing: $(basename "$pkg")"
            echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
                --armor --detach-sign "$pkg"
        fi
    done
else
    echo "WARNING: OTA directory not found: $OTA_DIR"
fi

# Sign SBOM
if [ -f "output/sbom.json" ]; then
    echo "Signing SBOM..."
    echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
        --armor --detach-sign output/sbom.json
fi

echo "=== Signing Complete ==="
echo "Signed artefacts:"
find "$IMAGES_DIR" "$OTA_DIR" output/ -name "*.sig" 2>/dev/null || true
