#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
PASSED=0; FAILED=0
test_result() { if [[ "$2" == "PASS" ]]; then echo "✓ $1"; PASSED=$((PASSED+1)); else echo "✗ $1"; FAILED=$((FAILED+1)); fi; }
[[ -f "$LAYER_DIR/scripts/build-settingsd.sh" ]] && {
  head -1 "$LAYER_DIR/scripts/build-settingsd.sh" | grep -q '^#!/bin/bash' && test_result "Shebang" "PASS" || test_result "Shebang" "FAIL"
  grep -q 'set -euo pipefail' "$LAYER_DIR/scripts/build-settingsd.sh" && test_result "Strict mode" "PASS" || test_result "Strict mode" "FAIL"
  grep -q 'Verification Class:' "$LAYER_DIR/scripts/build-settingsd.sh" && test_result "Verification" "PASS" || test_result "Verification" "FAIL"
  grep -q 'dbus' "$LAYER_DIR/scripts/build-settingsd.sh" && test_result "D-Bus support" "PASS" || test_result "D-Bus support" "FAIL"
}
[[ -f "$LAYER_DIR/config/settings-config.yaml" ]] && test_result "Config exists" "PASS" || test_result "Config exists" "FAIL"
echo "Layer 5: $PASSED passed, $FAILED failed"; [[ $FAILED -eq 0 ]]
