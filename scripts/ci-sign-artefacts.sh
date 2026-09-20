#!/bin/bash
# CI Script: Sign Artefacts with GPG
# Usage: ci-sign-artefacts.sh <images_dir> <ota_dir>

set -euo pipefail

# CRITICAL: Capture repository root at start before any directory changes
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

IMAGES_DIR="${1:-output/images}"
OTA_DIR="${2:-output/ota}"

# Convert to absolute paths relative to repo root if not already absolute
[[ "$IMAGES_DIR" = /* ]] || IMAGES_DIR="$REPO_ROOT/$IMAGES_DIR"
[[ "$OTA_DIR" = /* ]] || OTA_DIR="$REPO_ROOT/$OTA_DIR"

echo "=== Signing Artefacts ==="
echo "Repository root: $REPO_ROOT"
echo "Images directory: $IMAGES_DIR"
echo "OTA directory: $OTA_DIR"

# Check if GPG key is available. Placeholder signatures are development-only.
if ! gpg --list-secret-keys 2>/dev/null | grep -q "AshipaOS Release"; then
    if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
        echo "ERROR: GPG private key not found for tag release; refusing placeholder signatures." >&2
        exit 1
    fi
    if [[ "${CI_ALLOW_PLACEHOLDER_SIGNATURES:-}" != "1" ]]; then
        echo "ERROR: GPG private key not found and development placeholder signatures are not enabled." >&2
        echo "Set CI_ALLOW_PLACEHOLDER_SIGNATURES=1 only for explicit development validation." >&2
        exit 1
    fi
    echo "WARNING: GPG private key not found. Using explicitly enabled development placeholders."
    echo "To enable production signing, set GPG_PRIVATE_KEY and GPG_PASSPHRASE secrets."

    # Create placeholder signature files for explicitly enabled development validation.
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
    
    # Sign SBOM with explicit path
    SBOM_FILE="$REPO_ROOT/output/sbom.json"
    if [ -f "$SBOM_FILE" ]; then
        echo "PLACEHOLDER_SIGNATURE" > "${SBOM_FILE}.sig"
        sha256sum "$SBOM_FILE" > "${SBOM_FILE}.sha256"
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

# Sign SBOM with explicit absolute path
SBOM_FILE="$REPO_ROOT/output/sbom.json"
if [ -f "$SBOM_FILE" ]; then
    echo "Signing SBOM..."
    echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
        --armor --detach-sign "$SBOM_FILE"
    cp -- "${SBOM_FILE}.asc" "${SBOM_FILE}.sig"
    sha256sum "$SBOM_FILE" > "${SBOM_FILE}.sha256"
fi

echo "=== Signing Complete ==="
echo "Signed artefacts:"
find "$IMAGES_DIR" "$OTA_DIR" "$REPO_ROOT/output/" -name "*.sig" 2>/dev/null || true
