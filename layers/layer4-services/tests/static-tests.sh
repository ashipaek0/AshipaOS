#!/bin/bash
# Static tests for Layer 4: Core System Services
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
PASSED=0
FAILED=0

test_result() {
    local test_name="$1"
    local result="$2"
    if [[ "$result" == "PASS" ]]; then
        echo "✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "✗ $test_name"
        FAILED=$((FAILED + 1))
    fi
}

test_shebang() { head -1 "$1" | grep -q '^#!/bin/bash' && echo "PASS" || echo "FAIL"; }
test_shell_strict() { grep -q 'set -euo pipefail' "$1" && echo "PASS" || echo "FAIL"; }
test_usage_function() { grep -q 'usage()' "$1" && echo "PASS" || echo "FAIL"; }
test_error_handling() { grep -q 'error()' "$1" && echo "PASS" || echo "FAIL"; }
test_executable() { [[ -x "$1" ]] && echo "PASS" || echo "FAIL"; }
test_no_hardcoding() { ! grep -qE '/dev/mmcblk|/sys/class/' "$1" && echo "PASS" || echo "FAIL"; }
test_verification_class() { grep -qE 'Verification Class:' "$1" && echo "PASS" || echo "FAIL"; }
test_dependencies() { grep -q 'Dependencies:\|layer3' "$1" && echo "PASS" || echo "FAIL"; }
test_evidence_dir() { [[ -d "$LAYER_DIR/evidence" ]] || mkdir -p "$LAYER_DIR/evidence" && echo "PASS" || echo "FAIL"; }
test_evidence_generation() { grep -q 'generate_evidence' "$1" && grep -q 'build-evidence.json' "$1" && echo "PASS" || echo "FAIL"; }
test_config_exists() { [[ -f "$LAYER_DIR/config/services-config.yaml" ]] && echo "PASS" || echo "FAIL"; }
test_services_section() { grep -q 'services:' "$LAYER_DIR/config/services-config.yaml" && echo "PASS" || echo "FAIL"; }
test_enabled_list() { grep -q 'enabled:' "$LAYER_DIR/config/services-config.yaml" && echo "PASS" || echo "FAIL"; }
test_preset_generation() { grep -q 'preset' "$1" && echo "PASS" || echo "FAIL"; }
test_systemd_support() { grep -q 'systemd' "$1" && echo "PASS" || echo "FAIL"; }

echo "Running Layer 4 Static Tests..."
echo "================================"

BUILD_SCRIPT="$LAYER_DIR/scripts/build-services.sh"
CONFIG_FILE="$LAYER_DIR/config/services-config.yaml"

if [[ -f "$BUILD_SCRIPT" ]]; then
    test_result "SC01: Shebang" "$(test_shebang "$BUILD_SCRIPT")"
    test_result "SC02: Strict mode" "$(test_shell_strict "$BUILD_SCRIPT")"
    test_result "SC03: Usage function" "$(test_usage_function "$BUILD_SCRIPT")"
    test_result "SC04: Error handling" "$(test_error_handling "$BUILD_SCRIPT")"
    test_result "SC05: Executable" "$(test_executable "$BUILD_SCRIPT")"
    test_result "SH01: No hardcoding" "$(test_no_hardcoding "$BUILD_SCRIPT")"
    test_result "SV01: Verification class" "$(test_verification_class "$BUILD_SCRIPT")"
    test_result "SV02: Dependencies" "$(test_dependencies "$BUILD_SCRIPT")"
    test_result "SE01: Evidence dir" "$(test_evidence_dir)"
    test_result "SE02: Evidence generation" "$(test_evidence_generation "$BUILD_SCRIPT")"
    test_result "SI01: Preset generation" "$(test_preset_generation "$BUILD_SCRIPT")"
    test_result "SI02: systemd support" "$(test_systemd_support "$BUILD_SCRIPT")"
else
    echo "✗ Build script not found"; FAILED=$((FAILED + 1))
fi

if [[ -f "$CONFIG_FILE" ]]; then
    test_result "SC01: Config exists" "$(test_config_exists)"
    test_result "SC02: Services section" "$(test_services_section)"
    test_result "SC03: Enabled list" "$(test_enabled_list)"
else
    echo "✗ Config file not found"; FAILED=$((FAILED + 1))
fi

echo "================================"
echo "Results: $PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
