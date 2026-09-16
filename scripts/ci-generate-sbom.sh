#!/bin/bash
# CI Script: Generate Software Bill of Materials (SBOM)
# Usage: ci-generate-sbom.sh <output_file>

set -euo pipefail

OUTPUT_FILE="${1:-output/sbom.json}"

echo "=== Generating SBOM ==="

# Get current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get git commit info
if git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_COMMIT=$(git rev-parse HEAD)
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "none")
else
    GIT_COMMIT="unknown"
    GIT_BRANCH="unknown"
    GIT_TAG="none"
fi

# Create SBOM JSON
cat > "$OUTPUT_FILE" << EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "$TIMESTAMP",
    "tools": [
      {
        "vendor": "AshipaOS",
        "name": "build-system",
        "version": "0.1.0"
      }
    ],
    "component": {
      "type": "operating-system",
      "name": "AshipaOS",
      "version": "${GIT_TAG:-0.1.0-alpha}",
      "description": "AshipaOS Bootable Image",
      "purl": "pkg:github/ashipaos/ashipaos@${GIT_COMMIT}"
    },
    "properties": [
      {
        "name": "git:commit",
        "value": "$GIT_COMMIT"
      },
      {
        "name": "git:branch",
        "value": "$GIT_BRANCH"
      },
      {
        "name": "git:tag",
        "value": "$GIT_TAG"
      }
    ]
  },
  "components": [
    {
      "type": "operating-system",
      "name": "Debian",
      "version": "bookworm",
      "purl": "pkg:deb/debian/bookworm",
      "supplier": {
        "name": "Debian Project"
      }
    },
    {
      "type": "framework",
      "name": "systemd",
      "version": "latest",
      "purl": "pkg:deb/debian/systemd"
    },
    {
      "type": "library",
      "name": "GStreamer",
      "version": "1.22+",
      "purl": "pkg:deb/debian/gstreamer1.0-tools",
      "scope": "optional"
    },
    {
      "type": "application",
      "name": "cloud-init",
      "version": "latest",
      "purl": "pkg:deb/debian/cloud-init",
      "scope": "optional"
    },
    {
      "type": "firmware",
      "name": "U-Boot",
      "version": "device-specific",
      "scope": "required"
    }
  ],
  "dependencies": []
}
EOF

echo "SBOM generated: $OUTPUT_FILE"
echo "Components included:"
jq -r '.components[] | "  - \(.name) (\(.version))"' "$OUTPUT_FILE"
