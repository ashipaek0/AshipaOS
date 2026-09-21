#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
grep -q 'partition_table: dos' "$CONFIG"
grep -q 'prepartition_gap' "$CONFIG"
grep -q 'install_a95x_boot_partition' "$SCRIPT"
printf '%s\n' 'A95X Layer 2 image-content contract: PASS'
