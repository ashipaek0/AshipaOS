#!/bin/bash
# Static tests for Layer 2: Partitioned Disk Image
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

# SC01: Shell script has shebang
test_shebang() {
    local file="$1"
    if head -1 "$file" | grep -q '^#!/usr/bin/env bash$'; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SC02: Shell script uses set -euo pipefail
test_shell_strict() {
    local file="$1"
    if grep -q 'set -Eeuo pipefail' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SC03: Shell script has usage function
test_usage_function() {
    local file="$1"
    if grep -q 'usage()' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SC04: Shell script has error handling
test_error_handling() {
    local file="$1"
    if grep -q 'error()' "$file" && grep -q 'trap' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SC05: Shell script is executable
test_executable() {
    local file="$1"
    if [[ -x "$file" ]]; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SH01: No hardcoded Raspberry Pi specific paths in generic scripts
test_no_pi_hardcoding() {
    local file="$1"
    if grep -qE '/mnt/mmcblk|/dev/mmcblk[0-9]' "$file" 2>/dev/null; then
        # Only fail if it's not in a target-specific context
        if ! grep -q '# Target-specific' "$file"; then
            echo "FAIL"
            return
        fi
    fi
    echo "PASS"
}

# SH02: No hardcoded Amlogic paths
test_no_amlogic_hardcoding() {
    local file="$1"
    if grep -qE '/dev/block/mmcblk|/sys/class/amhdmi' "$file" 2>/dev/null; then
        echo "FAIL"
        return
    fi
    echo "PASS"
}

# SH03: Hardware facts come from configuration or HAL
test_hardware_from_config() {
    local config_file="$1"
    if grep -q "partitions:" "$config_file" && grep -q "image_size_mb:" "$config_file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SV01: Verification class documented
test_verification_class() {
    local file="$1"
    if grep -q 'Verification Class: BUILD' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SV02: Dependencies documented
test_dependencies() {
    local file="$1"
    if grep -q 'Dependencies:' "$file" || grep -q 'layer1_rootfs' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SE01: Evidence directory exists
test_evidence_dir() {
    if [[ -d "$LAYER_DIR/evidence" ]] || mkdir -p "$LAYER_DIR/evidence"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SE02: Evidence generation capability
test_evidence_generation() {
    local file="$1"
    if grep -q 'generate_evidence' "$file" && grep -q 'build-evidence.json' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SE03: Evidence includes required fields
test_evidence_fields() {
    local file="$1"
    if grep -q '"task_id":' "$file" && grep -q '"verification_class":' "$file" && \
       grep -q '"runner":' "$file" && grep -q '"result":' "$file" && \
       grep -q '"commit_sha":' "$file" && grep -q '"ci_run_id":' "$file" && \
       grep -q '"ci_job_id":' "$file" && grep -q '"evidence_path":' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SD01: Depends on Layer 1
test_layer1_dependency() {
    local file="$1"
    if grep -q 'rootfs' "$file" || grep -q 'ROOTFS_IMAGE' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SP01: Partition creation logic exists
test_partition_logic() {
    local file="$1"
    if grep -q 'unit: sectors' "$file" && grep -q 'sfdisk --verify' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SP02: Filesystem creation logic exists
test_filesystem_logic() {
    local file="$1"
    if grep -qE '^mkfs vfat /dev/sda1$' "$file" && grep -qE '^mkfs ext4 /dev/sda2$' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SF01: fstab generation
test_fstab_generation() {
    local file="$1"
    if grep -q 'fstab' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SF02: full builds must not silently produce metadata without an image
test_no_metadata_fallback() {
    local file="$1"
    if grep -q 'metadata-only output is forbidden' "$file" && ! grep -q 'build_mode.*metadata_only' "$file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SF03: GitHub-hosted runners do not permit host loop devices or mounts.
test_userspace_image_access() {
    local file="$1"
    if grep -qE '(^|[;&|[:space:]])(losetup|chroot)([[:space:]]|$)' "$file"; then
        echo "FAIL"
        return
    fi
    if ! grep -q 'guestfish -a "\$image"' "$file"; then
        echo "FAIL"
        return
    fi
    if grep -q 'guestfish -a "\$IMAGE"' "$file"; then
        echo "FAIL"
        return
    fi
    echo "PASS"
}

# SI01: Image size configurable
test_image_size_config() {
    local config_file="$1"
    if grep -q 'image_size_mb:' "$config_file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SI02: Multiple architectures supported
test_multi_arch() {
    local config_file="$1"
    if grep -q 'arm64' "$config_file" && grep -q 'amd64' "$config_file"; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

# SB01: A95X uses the complete stock bundle, not split/placeholder blobs.
test_a95x_inputs() {
    local dir="$LAYER_DIR/files/a95x-f3-air"
    [[ -f "$dir/aml_sdc_burn.UBOOT" && -f "$dir/ddr-usb.bin" && -f "$dir/meson1.dtb" ]] || { echo FAIL; return; }
    [[ ! -e "$dir/bl301.bin" && ! -e "$dir/bl31.img" && ! -e "$dir/u-boot.bin" ]] || { echo FAIL; return; }
    [[ "$(stat -c%s "$dir/aml_sdc_burn.UBOOT")" -eq 1339248 ]] || { echo FAIL; return; }
    [[ "$(sha256sum "$dir/aml_sdc_burn.UBOOT" | awk '{print $1}')" == 4b8ec8af9304ed7f6372c0c84d4e13813cf39a005b4d80bdbf9dc443ee9c7d9e ]] || { echo FAIL; return; }
    [[ "$(sha256sum "$dir/ddr-usb.bin" | awk '{print $1}')" == 6446cd26ab8719ed6da4beb96bfb7b63b41e809a7cc79b46397afb625e459523 ]] || { echo FAIL; return; }
    [[ "$(od -An -tx1 -N4 "$dir/meson1.dtb" | tr -d ' \\n')" == d00dfeed ]] || { echo FAIL; return; }
    [[ "$(stat -c%s "$dir/meson1.dtb")" -eq 80329 ]] || { echo FAIL; return; }
    echo PASS
}

# SB02: the verified SD contract leaves the pre-partition gap zero-filled;
# stock USB-burning payloads are provenance-only, not raw image writes.
test_a95x_assembly() {
    local file="$1" config="$2"
    python3 - "$file" "$config" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
config = Path(sys.argv[2]).read_text()

# No aml_sdc_burn.UBOOT/ddr-usb.bin write may reintroduce the USB-burning path.
assert 'bs=1 count=442' not in script
assert 'bs=512 skip=1 seek=1' not in script
assert 'aml_sdc_burn.UBOOT" of="$image"' not in script
assert 'ddr-usb.bin" of="$image"' not in script

# Preserve the observed DOS/MBR layout and zero-gap contract.
assert 'label: dos' in script and 'efi_start=8192' in script
assert 'start_sector: 1' in config and 'end_sector: 8191' in config
assert 'contents: zero' in config and 'raw_sd_payload_writes: false' in config

# Match the inspected CoreELEC CFGLOAD semantics, including the observed
# bootm sequence; do not replace it with a direct/alternate boot command.
assert 'defenv' in script and 'autoscr ${loadaddr}' in script
cfgload = script[script.index('cat >"$WORK_DIR/CFGLOAD.txt"'):script.index('mkimage -A arm64 -T script -C none -n A95X-AUTOSCRIPT')]
expected = [
    'fatload \\${device} \\${devnr}:\\${partnr} \\${loadaddr} KERNEL.IMG',
    'fatload \\${device} \\${devnr}:\\${partnr} \\${dtb_mem_addr} dtb.img',
    'bootm \\${loadaddr}',
    'bootm start', 'bootm loados', 'bootm prep', 'bootm go',
]
positions = [cfgload.index(item) for item in expected]
assert positions == sorted(positions)
assert 'bootm 0x01000000 - 0x10000000' not in cfgload

assert 'bl301.bin\\|bl31.img' not in script
print('PASS')
PY
}

echo "Running Layer 2 Static Tests..."
echo "================================"

BUILD_SCRIPT="$LAYER_DIR/scripts/build-image.sh"
CONFIG_FILE="$LAYER_DIR/config/image-config.yaml"

# Test build script
if [[ -f "$BUILD_SCRIPT" ]]; then
    test_result "SC01: Build script has shebang" "$(test_shebang "$BUILD_SCRIPT")"
    test_result "SC02: Build script uses strict mode" "$(test_shell_strict "$BUILD_SCRIPT")"
    test_result "SC03: Build script has usage function" "$(test_usage_function "$BUILD_SCRIPT")"
    test_result "SC04: Build script has error handling" "$(test_error_handling "$BUILD_SCRIPT")"
    test_result "SC05: Build script is executable" "$(test_executable "$BUILD_SCRIPT")"
    
    test_result "SH01: No Pi-specific hardcoding" "$(test_no_pi_hardcoding "$BUILD_SCRIPT")"
    test_result "SH02: No Amlogic hardcoding" "$(test_no_amlogic_hardcoding "$BUILD_SCRIPT")"
    test_result "SH03: Hardware from configuration" "$(test_hardware_from_config "$CONFIG_FILE")"
    
    test_result "SV01: Verification class documented" "$(test_verification_class "$BUILD_SCRIPT")"
    test_result "SV02: Dependencies documented" "$(test_dependencies "$BUILD_SCRIPT")"
    
    test_result "SE01: Evidence directory exists" "$(test_evidence_dir)"
    test_result "SE02: Evidence generation capability" "$(test_evidence_generation "$BUILD_SCRIPT")"
    test_result "SE03: Evidence includes required fields" "$(test_evidence_fields "$BUILD_SCRIPT")"
    
    test_result "SD01: Depends on Layer 1" "$(test_layer1_dependency "$BUILD_SCRIPT")"
    
    test_result "SP01: Partition creation logic" "$(test_partition_logic "$BUILD_SCRIPT")"
    test_result "SP02: Filesystem creation logic" "$(test_filesystem_logic "$BUILD_SCRIPT")"
    test_result "SF01: fstab generation" "$(test_fstab_generation "$BUILD_SCRIPT")"
    test_result "SF02: No metadata-only fallback" "$(test_no_metadata_fallback "$BUILD_SCRIPT")"
    test_result "SF03: Userspace image access only" "$(test_userspace_image_access "$BUILD_SCRIPT")"
else
    echo "✗ Build script not found"
    ((FAILED++))
fi

# Test configuration
if [[ -f "$CONFIG_FILE" ]]; then
    test_result "SI01: Image size configurable" "$(test_image_size_config "$CONFIG_FILE")"
    test_result "SI02: Multiple architectures supported" "$(test_multi_arch "$CONFIG_FILE")"
    test_result "SB01: Stock A95X inputs" "$(test_a95x_inputs)"
    test_result "SB02: zero-gap SD assembly without raw USB writes" "$(test_a95x_assembly "$BUILD_SCRIPT" "$CONFIG_FILE")"
else
    echo "✗ Configuration file not found"
    ((FAILED++))
fi

echo "================================"
echo "Results: $PASSED passed, $FAILED failed"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
