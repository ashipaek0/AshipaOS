#!/usr/bin/env bash
set -Eeuo pipefail
mount_dir=${SOURCE_MOUNT:-/run/iso}; explicit=${INSTALL_SOURCE:-}; devroot=${SOURCE_DEV_ROOT:-/dev}
[[ "$devroot" == /dev || "${SOURCE_TEST_MODE:-}" == 1 ]] || exit 1
mkdir -p "$mount_dir"
if [[ -n "$explicit" ]]; then
  [[ "$explicit" == /dev/* ]] || { echo 'invalid installer source argument' >&2; exit 1; }
  candidates=("$devroot/${explicit#/dev/}")
else
  shopt -s nullglob
  candidates=("$devroot"/sr* "$devroot"/sd*[0-9] "$devroot"/sd[a-z] "$devroot"/nvme*n*p[0-9] "$devroot"/nvme*n1 "$devroot"/mmcblk*p[0-9] "$devroot"/mmcblk[0-9])
fi
for candidate in "${candidates[@]}"; do
  [[ -b "$candidate" || ( "${SOURCE_TEST_MODE:-}" == 1 && "$devroot" != /dev && -f "$candidate" ) ]] || continue
  umount "$mount_dir" 2>/dev/null || true
  if mount -o ro,nosuid,nodev,noexec "$candidate" "$mount_dir" 2>/dev/null &&
     [[ -s "$mount_dir/install/appliance.img.zst" && -s "$mount_dir/install/appliance.img.manifest" ]]; then
    readlink -f -- "$candidate" 2>/dev/null || printf '%s\n' "$candidate"
    exit 0
  fi
done
exit 1