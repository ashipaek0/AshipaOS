#!/usr/bin/env bash
# Layer 2 image-content contract.
#   image-content-tests.sh            -> static contract only (config + script grep)
#   image-content-tests.sh <image>    -> also inspects the built image
#                                        (partition table always; file contents
#                                        when ASHIPAOS_IMAGE_DEEP=1 and guestfish exist)
# Previously the image argument was accepted by CI but silently ignored, so the
# "Gate A95X image contents" step passed for any image, including a broken one.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
IMAGE="${1:-}"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

grep -q 'partition_table: dos' "$CONFIG" || fail "config: partition_table: dos"
grep -q 'prepartition_gap' "$CONFIG" || fail "config: prepartition_gap"
grep -q 'install_a95x_boot_partition' "$SCRIPT" || fail "build script: install_a95x_boot_partition"

if [[ -z "$IMAGE" ]]; then
    printf '%s\n' 'A95X Layer 2 image-content contract: PASS (static only; no image given)'
    exit 0
fi

[[ -f "$IMAGE" && -s "$IMAGE" ]] || fail "image missing or empty: $IMAGE"
command -v sfdisk >/dev/null || fail "sfdisk is required to inspect $IMAGE"

table="$(sfdisk -d "$IMAGE")"
grep -q '^label: dos$' <<<"$table" || fail "partition table is not DOS/MBR"
grep -Eq 'start= *8192,.*type=c' <<<"$table" || fail "partition 1 must start at sector 8192 with type c"
grep -Eq 'start= *532480,.*type=83' <<<"$table" || fail "partition 2 must start at sector 532480 with type 83"
[[ "$(dd if="$IMAGE" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d " \n")" == "55aa" ]] || fail "missing MBR boot signature"
# FAT16 boot partition begins at sector 8192: check the BPB filesystem type string and label.
fat_type="$(dd if="$IMAGE" bs=512 skip=8192 count=1 status=none | dd bs=1 skip=54 count=8 status=none)"
[[ "$fat_type" == "FAT16   " ]] || fail "boot partition is not FAT16 (got: '$fat_type')"
fat_label="$(dd if="$IMAGE" bs=512 skip=8192 count=1 status=none | dd bs=1 skip=43 count=11 status=none)"
[[ "$fat_label" == "A95XBOOT   " ]] || fail "boot partition label is not A95XBOOT (got: '$fat_label')"

if [[ "${ASHIPAOS_IMAGE_DEEP:-0}" == 1 ]]; then
    command -v guestfish >/dev/null || fail "ASHIPAOS_IMAGE_DEEP=1 requires guestfish"
    export LIBGUESTFS_BACKEND="${LIBGUESTFS_BACKEND:-direct}"
    boot_ls="$(guestfish --ro -a "$IMAGE" -m /dev/sda2 -m /dev/sda1:/boot ls /boot)"
    for f in AML_AUTOSCRIPT CFGLOAD KERNEL.IMG dtb.img manifest; do
        grep -Fxq "$f" <<<"$boot_ls" || fail "boot partition is missing $f"
    done
    for f in /etc/fstab /usr/libexec/ashipaos-jellyfin-mpv-shim; do
        [[ "$(guestfish --ro -a "$IMAGE" -m /dev/sda2 is-file "$f")" == true ]] || fail "root filesystem is missing $f"
    done
fi

printf '%s\n' 'A95X Layer 2 image-content contract: PASS'
