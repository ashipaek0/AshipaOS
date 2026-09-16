#!/bin/bash
# Layer 2: Build Bootable Disk Image with Kernel and Bootloader
# Verification Class: VM (qemu boot test), HARDWARE (physical boot)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/image-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
WORK_DIR="${WORK_DIR:-/tmp/layer2-work}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/output}"
ROOTFS_IMAGE="${1:-}"
TARGET="${2:-x86_64}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <rootfs-image> <target>

Build a bootable disk image from Layer 1 rootfs.

Arguments:
    rootfs-image    Path to Layer 1 rootfs tarball or directory
    target          Target device (x86_64, a95x-f3-air)

Options:
    -h, --help      Show this help message
    --validate      Validate configuration only
    --size SIZE     Override image size in MB (default: from config)

Verification Class: VM, HARDWARE
Dependencies: Layer 1 (rootfs), qemu-utils, parted, dosfstools, e2fsprogs
EOF
    exit 0
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        log "Cleaning up work directory: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT

validate_config() {
    log "Validating image configuration..."
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Check required fields exist
    if ! grep -q "image_size_mb:" "$CONFIG_FILE"; then
        error "Missing 'image_size_mb' in configuration"
    fi
    if ! grep -q "partitions:" "$CONFIG_FILE"; then
        error "Missing 'partitions' section in configuration"
    fi
    
    log "Configuration validation passed"
}

parse_config() {
    # Simple YAML parsing for key values
    IMAGE_SIZE_MB=$(grep "image_size_mb:" "$CONFIG_FILE" | awk '{print $2}')
    EFI_SIZE_MB=$(grep -A5 "partitions:" "$CONFIG_FILE" | grep "efi:" | awk '{print $2}' | head -1)
    ROOT_SIZE_MB=$(grep -A5 "partitions:" "$CONFIG_FILE" | grep "root:" | awk '{print $2}' | head -1)
    
    : "${IMAGE_SIZE_MB:=4096}"
    : "${EFI_SIZE_MB:=256}"
    : "${ROOT_SIZE_MB:=3584}"
    
    log "Image configuration: total=${IMAGE_SIZE_MB}MB, efi=${EFI_SIZE_MB}MB, root=${ROOT_SIZE_MB}MB"
}

create_partitions() {
    local img_file="$1"
    
    log "Creating partition table on $img_file"
    
    # Create GPT partition table
    parted -s "$img_file" mklabel gpt
    
    # Create EFI partition (FAT32, bootable)
    parted -s "$img_file" mkpart primary fat32 1MiB "${EFI_SIZE_MB}MiB"
    parted -s "$img_file" set 1 boot on
    parted -s "$img_file" name 1 "EFI System"
    
    # Create root partition (ext4)
    parted -s "$img_file" mkpart primary ext4 "${EFI_SIZE_MB}MiB" 100%
    parted -s "$img_file" name 2 "RootFS"
    
    log "Partition table created successfully"
}

create_filesystems() {
    local img_file="$1"
    local loop_dev
    
    log "Creating filesystems..."
    
    # Set up loop device
    loop_dev=$(losetup -f --show "$img_file")
    trap "losetup -d '$loop_dev' 2>/dev/null; cleanup" RETURN
    
    # Create FAT32 EFI partition
    mkfs.vfat -F 32 -n "EFI" "${loop_dev}p1"
    
    # Create ext4 root partition
    mkfs.ext4 -L "RootFS" -E lazy_itable_init=0,lazy_journal_init=0 "${loop_dev}p2"
    
    log "Filesystems created successfully"
}

mount_and_populate() {
    local img_file="$1"
    local rootfs_source="$2"
    local mnt_point="$WORK_DIR/mnt"
    local efi_point="$WORK_DIR/efi"
    local loop_dev
    
    mkdir -p "$mnt_point" "$efi_point"
    
    # Set up loop device with partition scanning
    loop_dev=$(losetup -f --show -P "$img_file")
    trap "losetup -d '$loop_dev' 2>/dev/null; cleanup" RETURN
    
    # Wait for partitions to appear
    sleep 2
    
    # Mount partitions
    mount "${loop_dev}p2" "$mnt_point"
    mount "${loop_dev}p1" "$efi_point"
    
    log "Extracting rootfs to image..."
    
    if [[ -f "$rootfs_source" ]]; then
        # Source is a tarball
        tar -xzf "$rootfs_source" -C "$mnt_point"
    elif [[ -d "$rootfs_source" ]]; then
        # Source is a directory
        cp -a "$rootfs_source"/. "$mnt_point/"
    else
        error "Rootfs source not found: $rootfs_source"
    fi
    
    # Create basic directory structure if missing
    mkdir -p "$mnt_point"/{boot,dev,proc,sys,run,tmp}
    
    # Copy bootloader files (placeholder - actual kernel/DTB from build process)
    log "Installing bootloader stubs..."
    mkdir -p "$efi_point/EFI/BOOT"
    echo "# EFI Boot Stub" > "$efi_point/EFI/BOOT/BOOTAA64.EFI"
    echo "# Kernel stub" > "$mnt_point/boot/Image"
    mkdir -p "$mnt_point/boot/dtbs"
    echo "# Device Tree Blob" > "$mnt_point/boot/dtbs/generic-dtb.dtb"
    
    # Create fstab
    cat > "$mnt_point/etc/fstab" <<EOF
# /etc/fstab: static file system information
PARTUUID=00000000-01  /boot/efi  vfat    defaults      0  2
PARTUUID=00000000-02  /          ext4    defaults,noatime  0  1
tmpfs                 /tmp       tmpfs   defaults      0  0
EOF
    
    # Unmount
    umount "$efi_point"
    umount "$mnt_point"
    
    log "Image populated successfully"
}

generate_evidence() {
    local img_file="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    mkdir -p "$EVIDENCE_DIR"
    
    local img_size
    img_size=$(stat -c%s "$img_file" 2>/dev/null || echo "0")
    local img_hash
    img_hash=$(sha256sum "$img_file" 2>/dev/null | awk '{print $1}' || echo "pending")
    
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{
    "layer": 2,
    "verification_class": ["VM", "HARDWARE"],
    "timestamp": "$timestamp",
    "build_host": "$(hostname)",
    "target": "$TARGET",
    "artefacts": {
        "image_path": "$img_file",
        "image_size_bytes": $img_size,
        "image_sha256": "$img_hash"
    },
    "configuration": {
        "total_size_mb": $IMAGE_SIZE_MB,
        "efi_size_mb": $EFI_SIZE_MB,
        "root_size_mb": $ROOT_SIZE_MB
    },
    "dependencies": {
        "layer1_rootfs": "$ROOTFS_IMAGE"
    },
    "build_parameters": {
        "partition_table": "gpt",
        "efi_filesystem": "vfat",
        "root_filesystem": "ext4"
    },
    "tests_required": [
        "qemu_boot_test",
        "partition_integrity",
        "filesystem_check"
    ]
}
EOF
    
    log "Evidence generated: $EVIDENCE_DIR/build-evidence.json"
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
    fi
    
    if [[ "${1:-}" == "--validate" ]]; then
        validate_config
        echo "Configuration valid"
        exit 0
    fi
    
    if [[ -z "$ROOTFS_IMAGE" || -z "$TARGET" ]]; then
        error "Missing required arguments. Use --help for usage."
    fi
    
    log "Starting Layer 2 build: target=$TARGET"
    
    # Validate prerequisites
    command -v parted >/dev/null || error "parted not found"
    command -v mkfs.vfat >/dev/null || error "dosfstools not found"
    command -v mkfs.ext4 >/dev/null || error "e2fsprogs not found"
    
    validate_config
    parse_config
    
    # Create output filename
    local img_name="ashipaos-${TARGET}-$(date +%Y%m%d).img"
    local img_path="$OUTPUT_DIR/$img_name"
    mkdir -p "$OUTPUT_DIR"
    
    # Create sparse image file
    log "Creating disk image: $img_path (${IMAGE_SIZE_MB}MB)"
    truncate -s "${IMAGE_SIZE_MB}M" "$img_path"
    
    create_partitions "$img_path"
    create_filesystems "$img_path"
    mount_and_populate "$img_path" "$ROOTFS_IMAGE"
    
    generate_evidence "$img_path"
    
    log "Layer 2 build complete: $img_path"
    echo "$img_path"
}

main "$@"
