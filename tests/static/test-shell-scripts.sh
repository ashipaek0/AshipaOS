#!/usr/bin/env bash
# Layer 0 STATIC: every shell script in the repo must pass `bash -n`.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
while IFS= read -r f; do
  if ! bash -n "$f"; then
    echo "SYNTAX-FAIL: $f"
    fail=1
  fi
done < <(find "$ROOT" -path "$ROOT/.git" -prune -o -name '*.sh' -print)

rootfs_repack_scripts=(
  "$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
  "$ROOT/layers/layer3-display/scripts/build-display.sh"
  "$ROOT/layers/layer4-services/scripts/build-services.sh"
  "$ROOT/scripts/setup-build-environment.sh"
)
for script in "${rootfs_repack_scripts[@]}"; do
  for pseudo_dir in dev proc sys run; do
    if ! grep -Fq -- "--exclude='./$pseudo_dir/*'" "$script"; then
      echo "ROOTFS-TAR-AUDIT-FAIL: $script must exclude ./$pseudo_dir/*"
      fail=1
    fi
  done
done
if [ "$fail" -ne 0 ]; then
  echo "test-shell-scripts: FAIL"
  exit 1
fi
echo "test-shell-scripts: PASS"
