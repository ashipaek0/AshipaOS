#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
grep -q 'a95x-f3-air' "$SCRIPT" "$CONFIG"
grep -q 'fat16' "$CONFIG"
grep -q 'RootFS' "$CONFIG"
printf '%s\n' 'A95X Layer 2 static contract: PASS'
