#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
grep -q 'label: gpt' "$SCRIPT"
grep -q 'install_x86_64_bootloader' "$SCRIPT"
grep -q 'BOOTX64.EFI' "$SCRIPT"
grep -q 'x86_64' "$CONFIG"
printf '%s\n' 'x86_64 Layer 2 static contract: PASS'
