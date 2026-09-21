#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
CONFIG="$ROOT/layers/layer1-rootfs/config/rootfs-config.yaml"
grep -q 'arm64' "$SCRIPT" "$CONFIG"
printf '%s\n' 'A95X Layer 1 contract: PASS'
