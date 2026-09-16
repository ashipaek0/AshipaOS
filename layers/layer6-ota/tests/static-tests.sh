#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
PASSED=0; FAILED=0
test_result() { if [[ "$2" == "PASS" ]]; then echo "✓ $1"; PASSED=$((PASSED+1)); else echo "✗ $1"; FAILED=$((FAILED+1)); fi; }
[[ -f "$LAYER_DIR/scripts/build-ota.sh" ]] && {
  head -1 "$LAYER_DIR/scripts/build-ota.sh" | grep -q '^#!/bin/bash' && test_result "Shebang" "PASS" || test_result "Shebang" "FAIL"
  grep -q 'set -euo pipefail' "$LAYER_DIR/scripts/build-ota.sh" && test_result "Strict" "PASS" || test_result "Strict" "FAIL"
  grep -q 'Verification Class:' "$LAYER_DIR/scripts/build-ota.sh" && test_result "Verification" "PASS" || test_result "Verification" "FAIL"
  grep -q 'A/B' "$LAYER_DIR/scripts/build-ota.sh" && test_result "AB slots" "PASS" || test_result "AB slots" "FAIL"
}
[[ -f "$LAYER_DIR/config/ota-config.yaml" ]] && test_result "Config" "PASS" || test_result "Config" "FAIL"
echo "Layer 6: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]
