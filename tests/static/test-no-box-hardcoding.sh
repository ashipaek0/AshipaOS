#!/usr/bin/env bash
# Layer 0 STATIC (target isolation, guide §1.4): generic trees must not
# hard-code Amlogic box-specific values. Box configuration belongs under
# build/targets/amlogic/boxes/ only.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
for d in "$ROOT/packages" "$ROOT/rootfs-overlay"; do
  if [ -d "$d" ] && grep -RniE 'a95x|f3-air' "$d" 2>/dev/null; then
    echo "BOX-HARDCODING found under $d"
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  echo "test-no-box-hardcoding: FAIL"
  exit 1
fi
echo "test-no-box-hardcoding: PASS"
