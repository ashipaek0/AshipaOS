#!/bin/bash
# AshipaOS GitHub Secrets Configuration Guide
# This script generates the necessary key material and provides instructions
# for configuring GitHub Repository Secrets.

set -euo pipefail

echo "=== AshipaOS GitHub Secrets Setup ==="
echo ""
echo "This script will generate local key material and provide instructions"
echo "for adding secrets to your GitHub repository."
echo ""
echo "Required Secrets:"
echo "-----------------"
echo "1. GPG_PRIVATE_KEY (Required for Layer 10 signing)"
echo "2. GPG_PASSPHRASE (Required for Layer 10 signing)"
echo "3. AWS_ACCESS_KEY_ID (Optional for S3 artefact storage)"
echo "4. AWS_SECRET_ACCESS_KEY (Optional for S3 artefact storage)"
echo "5. HARDWARE_LAB_TOKEN (Optional for hardware lab API access)"
echo ""

# Create a temporary directory for key generation
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Ensure output directory exists
mkdir -p output

# --- 1. Generate GPG Key Pair for Artefact Signing ---
echo "[1/3] Generating GPG key pair for release signing..."
GPG_KEY_NAME="AshipaOS Release Bot"
GPG_KEY_EMAIL="release@ashipaos.local"

cat > "$TEMP_DIR/gpg_batch" <<EOF
%echo Generating AshipaOS Release Key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GPG_KEY_NAME
Name-Email: $GPG_KEY_EMAIL
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

gpg --batch --gen-key "$TEMP_DIR/gpg_batch" 2>/dev/null

# Export private key
GPG_PRIVATE_KEY=$(gpg --armor --export-secret-keys "$GPG_KEY_EMAIL")

echo ""
echo "✅ GPG Key Generated."
echo "   Secret Name: GPG_PRIVATE_KEY"
echo "   Value: (See generated file: output/gpg_private_key.asc)"
echo "$GPG_PRIVATE_KEY" > output/gpg_private_key.asc

# Generate a secure passphrase (if you want to protect the key, though %no-protection was used above for CI ease)
# For CI, we typically use a key without passphrase protection OR store the passphrase separately.
# Here we generate a random passphrase to store as a secret if you choose to protect the key later.
GPG_PASSPHRASE=$(openssl rand -base64 32)
echo "   Secret Name: GPG_PASSPHRASE"
echo "   Value: (See generated file: output/gpg_passphrase.txt)"
echo "$GPG_PASSPHRASE" > output/gpg_passphrase.txt

# --- 2. Generate AWS Credentials (Mock/Placeholder) ---
echo ""
echo "[2/3] Preparing AWS credentials template..."
echo "   Note: You must create these in your AWS IAM Console."
echo "   Required Permissions: s3:PutObject, s3:DeleteObject on your artefact bucket."
echo ""
echo "   Secret Name: AWS_ACCESS_KEY_ID"
echo "   Secret Name: AWS_SECRET_ACCESS_KEY"
echo "   (Values must be created in AWS IAM, not generated here)"

# --- 3. Hardware Lab Token ---
echo ""
echo "[3/3] Preparing Hardware Lab Token template..."
LAB_TOKEN=$(openssl rand -hex 32)
echo "   Secret Name: HARDWARE_LAB_TOKEN"
echo "   Value: $LAB_TOKEN"
echo "   (Add this to your hardware-lab server configuration)"

echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Go to your GitHub Repository -> Settings -> Secrets and variables -> Actions"
echo ""
echo "2. Add the following secrets:"
echo ""
echo "   🔑 GPG_PRIVATE_KEY"
echo "      Copy the contents of: output/gpg_private_key.asc"
echo ""
echo "   🔑 GPG_PASSPHRASE"
echo "      Copy the contents of: output/gpg_passphrase.txt"
echo "      (Or leave empty if you generated a key without protection)"
echo ""
echo "   🔑 AWS_ACCESS_KEY_ID (Optional)"
echo "      From your AWS IAM User"
echo ""
echo "   🔑 AWS_SECRET_ACCESS_KEY (Optional)"
echo "      From your AWS IAM User"
echo ""
echo "   🔑 HARDWARE_LAB_TOKEN (Optional)"
echo "      Use the generated token above or your existing lab token"
echo ""
echo "3. Verify setup by running a workflow dispatch:"
echo "   gh workflow run build-images.yml --ref main"
echo ""
echo "Setup complete. Keys saved to ./output/"
