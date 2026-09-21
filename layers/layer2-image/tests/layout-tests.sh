#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
bash "$SCRIPT" --layout-only "$TMP"
sfdisk --verify "$TMP" >/dev/null
fdisk -l "$TMP" | grep -q 'FAT16'
printf '%s\n' 'A95X Layer 2 layout contract: PASS'
