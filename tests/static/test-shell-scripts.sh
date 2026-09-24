#!/usr/bin/env bash
# STATIC: every tracked shell script parses, is executable, and passes
# lints with shellcheck (errors and warnings); rootfs repackers exclude pseudo filesystems.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail=0
mapfile -t scripts < <(git ls-files -- '*.sh' 'rootfs-overlay/usr/libexec/*' 'layers/*/files/usr/libexec/*')
for f in "${scripts[@]}"; do
  [[ -f "$f" ]] || continue
  if ! bash -n "$f"; then echo "SYNTAX-FAIL: $f"; fail=1; fi
  [[ -x "$f" ]] || { echo "NOT-EXECUTABLE: $f"; fail=1; }
done
if command -v shellcheck >/dev/null; then
  shellcheck --severity=warning --external-sources "${scripts[@]}" || fail=1
else
  echo "shellcheck not installed; skipping lint" >&2
fi

rootfs_packer=layers/layer1-rootfs/scripts/build-rootfs.sh
for pseudo_dir in dev proc sys run; do
  grep -Fq -- "--exclude='./$pseudo_dir/*'" "$rootfs_packer" \
    || { echo "ROOTFS-TAR-AUDIT-FAIL: $rootfs_packer must exclude ./$pseudo_dir/*"; fail=1; }
done
if [ "$fail" -ne 0 ]; then
  echo "test-shell-scripts: FAIL"
  exit 1
fi
echo "test-shell-scripts: PASS"
