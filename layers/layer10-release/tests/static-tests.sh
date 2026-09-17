#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
PASSED=0; FAILED=0
test_result() { if [[ "$2" == "PASS" ]]; then echo "✓ $1"; PASSED=$((PASSED+1)); else echo "✗ $1"; FAILED=$((FAILED+1)); fi; }
for f in "$LAYER_DIR"/scripts/*.sh; do
  [[ -f "$f" ]] && {
    if head -1 "$f" | grep -q '^#!/usr/bin/env bash'; then test_result "Shebang $(basename "$f")" PASS; else test_result "Shebang $(basename "$f")" FAIL; fi
    if grep -q 'set -Eeuo pipefail' "$f"; then test_result "Strict $(basename "$f")" PASS; else test_result "Strict $(basename "$f")" FAIL; fi
    if grep -q 'Verification Class:' "$f"; then test_result "Verification $(basename "$f")" PASS; else test_result "Verification $(basename "$f")" FAIL; fi
  }
done
if [[ -d "$LAYER_DIR/config" ]]; then test_result "Config dir" PASS; else test_result "Config dir" FAIL; fi
# shellcheck disable=SC2016
if grep -Eq 'for img in .*IMAGES_DIR.*target.*\*\.img' "$LAYER_DIR/scripts/build-10-release.sh"; then test_result "Consumes Layer 2 images" PASS; else test_result "Consumes Layer 2 images" FAIL; fi
if ! grep -q 'PLACEHOLDER IMAGE' "$LAYER_DIR/scripts/build-10-release.sh"; then test_result "No placeholder releases" PASS; else test_result "No placeholder releases" FAIL; fi
echo "Layer ${LAYER_DIR##*/}: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
