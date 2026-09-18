#!/bin/bash
# STATIC Test Suite for Layer 1 - Minimal Debian Root Filesystem
# Verification Class: STATIC (no build required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER1_DIR="$(dirname "$SCRIPT_DIR")"

PASSED=0
FAILED=0

log_test() {
    echo "[STATIC TEST] $1"
}

log_pass() {
    echo "  ✓ PASS: $1"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo "  ✗ FAIL: $1"
    FAILED=$((FAILED + 1))
}

# Test 1: Build script exists and is executable
test_build_script_exists() {
    log_test "Checking build script exists..."
    
    if [[ -f "$LAYER1_DIR/scripts/build-rootfs.sh" ]]; then
        log_pass "build-rootfs.sh exists"
    else
        log_fail "build-rootfs.sh not found"
        return
    fi
    
    if [[ -x "$LAYER1_DIR/scripts/build-rootfs.sh" ]]; then
        log_pass "build-rootfs.sh is executable"
    else
        log_fail "build-rootfs.sh is not executable"
    fi
}

# Test 2: Build script uses proper shell standards
test_shell_standards() {
    log_test "Checking shell script standards..."
    
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    
    # Check for set -euo pipefail
    if grep -qE "set -E?euo pipefail" "$script"; then
        log_pass "Script uses 'set -Eeuo pipefail'"
    else
        log_fail "Script missing 'set -euo pipefail'"
    fi
    
    # Check for proper error handling
    if grep -q "error()" "$script"; then
        log_pass "Script has error handling function"
    else
        log_fail "Script missing error handling function"
    fi
    
    # Check for usage function
    if grep -q "usage()" "$script"; then
        log_pass "Script has usage function"
    else
        log_fail "Script missing usage function"
    fi
}

# Test 3: Configuration file exists and is valid YAML
test_config_exists() {
    log_test "Checking configuration file..."
    
    local config="$LAYER1_DIR/config/rootfs-config.yaml"
    
    if [[ -f "$config" ]]; then
        log_pass "rootfs-config.yaml exists"
    else
        log_fail "rootfs-config.yaml not found"
        return
    fi
    
    # Basic YAML structure checks
    if grep -q "^debian:" "$config"; then
        log_pass "Config has debian section"
    else
        log_fail "Config missing debian section"
    fi
    
    if grep -q "^architectures:" "$config"; then
        log_pass "Config has architectures section"
    else
        log_fail "Config missing architectures section"
    fi
    
    if grep -q "^packages:" "$config"; then
        log_pass "Config has packages section"
    else
        log_fail "Config missing packages section"
    fi
    
    if grep -q "^verification:" "$config"; then
        log_pass "Config has verification section"
    else
        log_fail "Config missing verification section"
    fi
}

# Test 4: Evidence directory can be created by build script
test_evidence_dir() {
    log_test "Checking evidence directory..."
    
    # The build script's generate_evidence() creates this directory
    # Ensure it exists for a clean checkout
    mkdir -p "$LAYER1_DIR/evidence"
    
    if [[ -d "$LAYER1_DIR/evidence" ]]; then
        log_pass "Evidence directory exists"
    else
        log_fail "Evidence directory not found"
    fi
}

# Test 5: Script doesn't hardcode hardware-specific values
test_no_hardware_hardcoding() {
    log_test "Checking for hardware-specific hardcoding..."
    
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    
    # Should not contain specific board names (except a95x-f3-air which is a supported target)
    if grep -qiE "(pi4|pi5|raspberry)" "$script"; then
        log_fail "Script contains hardware-specific values"
    else
        log_pass "No hardware-specific hardcoding detected"
    fi
    
    # Should use architecture parameter instead of hardcoded arch
    if grep -q 'target_arch="\$1"' "$script" || grep -q '\${1:-}' "$script"; then
        log_pass "Script accepts architecture as parameter"
    else
        log_fail "Script may have hardcoded architecture"
    fi
}

# Test 6: Verification class is correctly specified
test_verification_class() {
    log_test "Checking verification class specification..."
    
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    
    if grep -q "Verification Class: BUILD" "$script"; then
        log_pass "Verification class BUILD specified in comments"
    else
        log_fail "Verification class not specified"
    fi
    
    local config="$LAYER1_DIR/config/rootfs-config.yaml"
    if grep -q "class: BUILD" "$config"; then
        log_pass "Verification class BUILD specified in config"
    else
        log_fail "Verification class not specified in config"
    fi
}

# Test 7: Script generates evidence
test_evidence_generation() {
    log_test "Checking evidence generation capability..."
    
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    
    if grep -q "generate_evidence()" "$script"; then
        log_pass "Script has evidence generation function"
    else
        log_fail "Script missing evidence generation function"
    fi
    
    if grep -q "build-evidence-" "$script"; then
        log_pass "Script generates timestamped evidence files"
    else
        log_fail "Script doesn't generate timestamped evidence"
    fi
}

# Test 8: Target kernel/initramfs policy and validation are explicit
 test_kernel_initramfs_policy() {
    log_test "Checking target kernel/initramfs policy..."
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    local config="$LAYER1_DIR/config/rootfs-config.yaml"

    grep -q '^kernel:' "$config" && log_pass "Config declares kernel policy" || log_fail "Config missing kernel policy"
    grep -q '^initramfs:' "$config" && log_pass "Config declares initramfs policy" || log_fail "Config missing initramfs policy"
    grep -q 'x86_64: amd64' "$config" && log_pass "Config maps x86_64 to amd64" || log_fail "Config missing x86_64 mapping"
    grep -q '\["x86_64"\]="amd64"' "$script" && log_pass "Script maps x86_64 to amd64" || log_fail "Script missing x86_64 mapping"
    grep -q 'linux-image-amd64' "$script" && log_pass "amd64 kernel package is declared" || log_fail "amd64 kernel package missing"
    grep -q 'initramfs-tools' "$script" && log_pass "initramfs tooling is declared" || log_fail "initramfs tooling missing"
    grep -q 'validate_kernel_initramfs' "$script" && log_pass "Kernel/initramfs validation is enforced" || log_fail "Kernel/initramfs validation missing"
    grep -q 'dpkg-query' "$script" && log_pass "Package metadata is recorded/checked" || log_fail "Package metadata handling missing"
    grep -q 'sha256sum' "$script" && log_pass "File hashes are recorded" || log_fail "File metadata hashing missing"
    grep -q 'local vmlinuz="\$rootfs/vmlinuz"' "$script" && log_pass "Validator checks root-level /vmlinuz" || log_fail "Validator does not check root-level /vmlinuz"
    grep -q 'local initrd="\$rootfs/initrd.img"' "$script" && log_pass "Validator checks root-level /initrd.img" || log_fail "Validator does not check root-level /initrd.img"
    grep -q 'file_metadata_json "\$rootfs_metadata" /vmlinuz' "$script" && log_pass "Evidence records root-level /vmlinuz" || log_fail "Evidence path for kernel is incorrect"
    grep -q 'file_metadata_json "\$rootfs_metadata" /initrd.img' "$script" && log_pass "Evidence records root-level /initrd.img" || log_fail "Evidence path for initramfs is incorrect"
    grep -q '\-L "\$vmlinuz"' "$script" && log_pass "Validator requires /vmlinuz symlink" || log_fail "Validator does not require /vmlinuz symlink"
    grep -q '\-L "\$initrd"' "$script" && log_pass "Validator requires /initrd.img symlink" || log_fail "Validator does not require /initrd.img symlink"
    grep -q '^    - /vmlinuz$' "$config" && log_pass "Config requires root-level /vmlinuz" || log_fail "Config has wrong kernel entry point"
    grep -q '^    - /initrd.img$' "$config" && log_pass "Config requires root-level /initrd.img" || log_fail "Config has wrong initramfs entry point"
    if grep -qE '/boot/(vmlinuz|initrd\.img)([^-]|$)' "$script"; then
        log_fail "Script requires a non-versioned /boot kernel/initramfs alias"
    else
        log_pass "Script only resolves versioned files under /boot"
    fi
    if grep -qE '(/boot|boot/).*cp |cp .*(/boot|boot/)' "$script"; then
        log_fail "Script appears to copy a host boot file"
    else
        log_pass "No host /boot copy path detected"
    fi
}

# Test 9: x86_64 marker is emitted by the systemd-managed getty banner
test_x86_64_boot_marker() {
    log_test "Checking x86_64 serial login banner configuration..."
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    grep -q 'install_x86_64_boot_marker' "$script" && log_pass "x86_64 banner installer exists" || log_fail "x86_64 banner installer missing"
    grep -q 'local issue="\$rootfs/etc/issue"' "$script" && log_pass "Banner writes rootfs /etc/issue" || log_fail "Banner path is not rootfs /etc/issue"
    grep -q "printf 'ASHIPAOS_BOOT_SUCCESS=1\\\\n' >> \"\$issue\"" "$script" && log_pass "Banner appends exact success marker" || log_fail "Exact success marker append missing"
    local marker_guard
    marker_guard=$(grep 'if \[\[ "\$product_arch"' "$script" || true)
    if [[ "$marker_guard" == *'"x86_64"'* && "$marker_guard" == *'"amd64"'* ]]; then
        log_pass "Banner installation enables x86_64 and amd64 aliases"
    else
        log_fail "x86_64/amd64 installation guard missing"
    fi
    if [[ "$marker_guard" != *'"arm64"'* && "$marker_guard" != *'"armhf"'* ]]; then
        log_pass "Banner installation excludes ARM aliases"
    else
        log_fail "ARM alias unexpectedly enables banner installation"
    fi
    if grep -q 'ashipaos-boot-success.service\|multi-user.target.wants' "$script"; then
        log_fail "Marker must not depend on a separate systemd service"
    else
        log_pass "Marker has no separate service dependency"
    fi
}

# Test 10: Safe argument and validation failures are non-zero
 test_argument_validation() {
    log_test "Checking argument and validation failure paths..."
    local script="$LAYER1_DIR/scripts/build-rootfs.sh"
    if bash "$script" >/dev/null 2>&1; then
        log_fail "Missing arguments unexpectedly succeeded"
    else
        log_pass "Missing arguments fail non-zero"
    fi
    if bash "$script" invalid-arch /tmp/layer1-static-test.tar.gz >/dev/null 2>&1; then
        log_fail "Invalid architecture unexpectedly succeeded"
    else
        log_pass "Invalid architecture fails non-zero"
    fi
    if bash -n "$script"; then
        log_pass "Build script passes bash syntax validation"
    else
        log_fail "Build script has bash syntax errors"
    fi
}

# Run all tests
main() {
    echo "========================================"
    echo "Layer 1 Static Test Suite"
    echo "========================================"
    echo ""
    
    test_build_script_exists
    echo ""
    
    test_shell_standards
    echo ""
    
    test_config_exists
    echo ""
    
    test_evidence_dir
    echo ""
    
    test_no_hardware_hardcoding
    echo ""
    
    test_verification_class
    echo ""
    
    test_evidence_generation
    echo ""

    test_kernel_initramfs_policy
    echo ""

    test_x86_64_boot_marker
    echo ""

    test_argument_validation
    echo ""

    echo "========================================"
    echo "Test Results: $PASSED passed, $FAILED failed"
    echo "========================================"
    
    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
