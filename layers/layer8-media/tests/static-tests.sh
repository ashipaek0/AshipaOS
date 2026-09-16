#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
PASSED=0; FAILED=0
test_result() { if [[ "$2" == "PASS" ]]; then echo "✓ $1"; PASSED=$((PASSED+1)); else echo "✗ $1"; FAILED=$((FAILED+1)); fi; }
for f in "$LAYER_DIR"/scripts/*.sh; do
  [[ -f "$f" ]] && {
    head -1 "$f" | grep -q '^#!/bin/bash' && test_result "Shebang $(basename $f)" "PASS" || test_result "Shebang $(basename $f)" "FAIL"
    grep -q 'set -euo pipefail' "$f" && test_result "Strict $(basename $f)" "PASS" || test_result "Strict $(basename $f)" "FAIL"
    grep -q 'Verification Class:' "$f" && test_result "Verification $(basename $f)" "PASS" || test_result "Verification $(basename $f)" "FAIL"
  }
done
[[ -d "$LAYER_DIR/config" ]] && test_result "Config dir" "PASS" || test_result "Config dir" "FAIL"
echo "Layer ${LAYER_DIR##*/}: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
