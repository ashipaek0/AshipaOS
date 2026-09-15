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
if [ "$fail" -ne 0 ]; then
  echo "test-shell-scripts: FAIL"
  exit 1
fi
echo "test-shell-scripts: PASS"
