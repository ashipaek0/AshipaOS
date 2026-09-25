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
# boot: FAT16, 256 MiB @8192
grep -Eq 'start= *8192, size= *524288, type=e, bootable' <<<"$table"
# root_a: ext4, 2048 MiB @532480 (directly after boot)
grep -Eq 'start= *532480, size= *4194304, type=83' <<<"$table"
# root_b: ext4, 2048 MiB @4726784 (directly after root_a)
grep -Eq 'start= *4726784, size= *4194304, type=83' <<<"$table"
# storage: ext4, 512 MiB @8921088 (directly after root_b)
grep -Eq 'start= *8921088, size= *1048576, type=83' <<<"$table"
[[ "$(grep -c 'start=' <<<"$table")" -eq 4 ]]
# A broken config must be rejected before anything is written.
sed 's/start_sector: 532480/start_sector: 532481/' "$ROOT/layers/layer2-image/config/image-config.yaml" >"$TMP/bad.yaml"
if ASHIPAOS_IMAGE_CONFIG="$TMP/bad.yaml" bash "$SCRIPT" --layout-only "$TMP/bad.img" 2>/dev/null; then
    echo 'FAIL: invalid layout configuration was accepted' >&2; exit 1
fi
[[ ! -e "$TMP/bad.img" ]]
printf '%s\n' 'A95X Layer 2 layout contract: PASS'
