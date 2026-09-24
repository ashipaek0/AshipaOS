#!/usr/bin/env bash
# Layer 2 layout gate: the partition layout alone, without a rootfs.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$SCRIPT" --layout-only "$TMP/layout.img" 2>/dev/null
sfdisk --verify "$TMP/layout.img" >/dev/null
table="$(sfdisk -d "$TMP/layout.img")"
grep -q '^label: dos$' <<<"$table"
grep -Eq 'start= *8192, size= *524288, type=e, bootable' <<<"$table"
grep -Eq 'start= *532480, size= *7340032, type=83' <<<"$table"
[[ "$(grep -c 'start=' <<<"$table")" -eq 2 ]]
# A broken config must be rejected before anything is written.
sed 's/start_sector: 532480/start_sector: 532481/' "$ROOT/layers/layer2-image/config/image-config.yaml" >"$TMP/bad.yaml"
if ASHIPAOS_IMAGE_CONFIG="$TMP/bad.yaml" bash "$SCRIPT" --layout-only "$TMP/bad.img" 2>/dev/null; then
    echo 'FAIL: invalid layout configuration was accepted' >&2; exit 1
fi
[[ ! -e "$TMP/bad.img" ]]
printf '%s\n' 'A95X Layer 2 layout contract: PASS'
