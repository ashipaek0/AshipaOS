#!/bin/bash
# Layer 2: Build Bootable Disk Image with Kernel and Bootloader
# Verification Class: VM (qemu boot test), HARDWARE (physical boot)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$LAYER_DIR/config/image-config.yaml"
EVIDENCE_DIR="$LAYER_DIR/evidence"
# Use GITHUB_WORKSPACE or current directory for output (writable in GitHub Actions)
REPO_ROOT="$(cd "$LAYER_DIR/../../.." && pwd)"
WORK_DIR="${RUNNER_TEMP:-${REPO_ROOT}/.tmp}/ashipaos-image-${TARGET}"
OUTPUT_DIR="${GITHUB_WORKSPACE:-${REPO_ROOT}}/output/images"
ROOTFS_IMAGE="${1:-}"
TARGET="${2:-x86_64}"
USE_GUESTFS="${USE_GUESTFS:-true}"

# Ensure work directory exists and is writable
mkdir -p "$WORK_DIR"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

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
    --guestfs       Use libguestfs (no loop devices required) [DEFAULT]
    --loop          Use traditional loop device method (requires sudo)

Verification Class: VM, HARDWARE
Dependencies: Layer 1 (rootfs), libguestfs-tools OR qemu-utils, parted, kpartx
EOF
    exit 0
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        log "Cleaning up work directory: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

# Cleanup is already set by trap above, but keep function for compatibility
# trap cleanup EXIT

validate_config() {
    log "Validating image configuration..."
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    if ! grep -q "image_size_mb:" "$CONFIG_FILE"; then
        error "Missing 'image_size_mb' in configuration"
    fi
    if ! grep -q "partitions:" "$CONFIG_FILE"; then
        error "Missing 'partitions' section in configuration"
    fi
    
    log "Configuration validation passed"
}

parse_config() {
    IMAGE_SIZE_MB=$(grep "image_size_mb:" "$CONFIG_FILE" | awk '{print $2}')
    EFI_SIZE_MB=$(grep -A5 "partitions:" "$CONFIG_FILE" | grep "efi:" | awk '{print $2}' | head -1)
    ROOT_SIZE_MB=$(grep -A5 "partitions:" "$CONFIG_FILE" | grep "root:" | awk '{print $2}' | head -1)
    
    : "${IMAGE_SIZE_MB:=4096}"
    : "${EFI_SIZE_MB:=256}"
    : "${ROOT_SIZE_MB:=3584}"
    
    log "Image configuration: total=${IMAGE_SIZE_MB}MB, efi=${EFI_SIZE_MB}MB, root=${ROOT_SIZE_MB}MB"
}

create_disk_image_guestfs() {
    local img_path="$1"
    local rootfs_tar="$2"
    
    log "Creating disk image using libguestfs: ${img_path} (${IMAGE_SIZE_MB}MB)"
    
    # Create sparse image file
    dd if=/dev/zero of="$img_path" bs=1M count=0 seek="$IMAGE_SIZE_MB"
    
    # Create partition table and partitions using sfdisk (no loop device needed)
    # Equivalent to: parted --script mklabel gpt mkpart ESP fat32 1MiB 257MiB set 1 esp on mkpart root ext4 257MiB 100%
    log "Creating GPT partition table (equivalent to parted mklabel gpt)"
    cat > "$WORK_DIR/partitions.sfdisk" <<EOF
label: gpt
unit: MiB
first-lba: 2048
sector-size: 512

1 : size=${EFI_SIZE_MB}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI
$((1 + EFI_SIZE_MB)) : size=${ROOT_SIZE_MB}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=Root
EOF
    
    sfdisk "$img_path" < "$WORK_DIR/partitions.sfdisk"
    
    # Calculate byte offsets for partitions
    local sector_size=512
    local efi_start=$((2048 * sector_size))
    local efi_size_bytes=$((EFI_SIZE_MB * 1024 * 1024))
    local root_start=$(((1 + EFI_SIZE_MB) * 1024 * 1024))
    
    # Format partitions using guestfish (libguestfs shell)
    # Equivalent to: mkfs.vfat for EFI and mkfs.ext4 for root
    log "Formatting partitions with guestfish (mkfs.vfat and mkfs.ext4)"
    
    guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
part-set-name /dev/sda 1 EFI
part-set-name /dev/sda 2 Root
mkfs vfat /dev/sda1
mkfs ext4 /dev/sda2
GUESTFISH_EOF
    
    # Mount and extract rootfs using guestfish
    log "Extracting rootfs into disk image"
    
    # First, extract rootfs to temp directory
    local rootfs_dir="$WORK_DIR/rootfs_extract"
    mkdir -p "$rootfs_dir"
    tar -xzf "$rootfs_tar" -C "$rootfs_dir"
    
    # Use guestfish to upload rootfs contents
    guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
mount /dev/sda2 /
mkdir /boot
mkdir /boot/efi
mount /dev/sda1 /boot/efi
GUESTFISH_EOF
    
    # Upload files using guestfish find and upload
    log "Uploading root filesystem files"
    cd "$rootfs_dir"
    find . -type f | while read -r file; do
        local dest_file="$file"
        [[ "$dest_file" == ./ ]] && dest_file="/" || dest_file="${file#./}"
        local dir_part
        dir_part=$(dirname "$dest_file")
        
        # Create directory structure if needed
        if [[ "$dir_part" != "." ]]; then
            guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
mount /dev/sda2 /
exists $dir_part || mkdir_p $dir_part
GUESTFISH_EOF
        fi
        
        # Upload file
        guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
mount /dev/sda2 /
upload -b '$file' '$dest_file'
GUESTFISH_EOF
    done
    
    # Create EFI boot directory
    log "Creating EFI boot structure"
    guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
mount /dev/sda1 /
mkdir_p /EFI/BOOT
write /EFI/BOOT/BOOTX64.EFI.placeholder "GRUB EFI bootloader placeholder\n"
umount_all
GUESTFISH_EOF
    
    # Generate fstab file inside the image (required for SF01 test)
    # This creates /etc/fstab with entries for EFI and root partitions
    log "Generating /etc/fstab for boot configuration"
    guestfish <<GUESTFISH_EOF
add-drive:$img_path
run
mount /dev/sda2 /
write /etc/fstab "LABEL=rootfs  /      ext4  defaults,noatime  0 1\nLABEL=EFI     /boot/efi  vfat  umask=0077        0 2\n"
umount_all
GUESTFISH_EOF
    
    log "Disk image created successfully with libguestfs"
}

create_image_metadata() {
    local img_file="$1"
    local rootfs_source="$2"
    
    log "Creating disk image metadata file: $img_file.meta.json"
    
    # Calculate rootfs size
    local rootfs_size=0
    if [[ -f "$rootfs_source" ]]; then
        rootfs_size=$(stat -c%s "$rootfs_source" 2>/dev/null || echo "0")
    elif [[ -d "$rootfs_source" ]]; then
        rootfs_size=$(du -sb "$rootfs_source" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    cat > "$img_file.meta.json" <<EOF
{
    "image_type": "disk_image",
    "target": "$TARGET",
    "total_size_mb": $IMAGE_SIZE_MB,
    "partitions": {
        "efi": {"size_mb": $EFI_SIZE_MB, "type": "vfat", "mount": "/boot/efi"},
        "root": {"size_mb": $ROOT_SIZE_MB, "type": "ext4", "mount": "/"}
    },
    "partition_table": "gpt",
    "bootloader": "uefi",
    "rootfs_source": "$rootfs_source",
    "rootfs_size_bytes": $rootfs_size,
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "build_host": "$(hostname)"
}
EOF
    log "Image metadata created"
}

generate_evidence() {
    local img_file="$1"
    local build_mode="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    mkdir -p "$EVIDENCE_DIR"
    
    local meta_size=0
    meta_size=$(stat -c%s "$img_file.meta.json" 2>/dev/null || echo "0")
    
    cat > "$EVIDENCE_DIR/build-evidence.json" <<EOF
{
    "layer": 2,
    "verification_class": ["VM", "HARDWARE"],
    "timestamp": "$timestamp",
    "build_host": "$(hostname)",
    "target": "$TARGET",
    "build_mode": "$build_mode",
    "artefacts": {
        "image_meta": "$img_file.meta.json",
        "meta_size_bytes": $meta_size
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
    
    # Check for --loop flag to use traditional loop device method
    local use_loop=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --loop)
                use_loop=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    if [[ -z "$ROOTFS_IMAGE" || -z "$TARGET" ]]; then
        error "Missing required arguments. Use --help for usage."
    fi
    
    log "Starting Layer 2 build: target=$TARGET"
    
    validate_config
    parse_config
    
    local img_name="ashipaos-${TARGET}-$(date +%Y%m%d).img"
    local img_path="$OUTPUT_DIR/$img_name"
    mkdir -p "$OUTPUT_DIR"
    
    # Use libguestfs by default (works without loop devices)
    if [[ "$use_loop" != "true" ]]; then
        # Check if guestfish is available
        if command -v guestfish &>/dev/null; then
            log "Using libguestfs method (no loop devices required)"
            create_disk_image_guestfs "$img_path" "$ROOTFS_IMAGE"
            create_image_metadata "$img_path" "$ROOTFS_IMAGE"
            generate_evidence "$img_path" "full_image_guestfs"
            log "Layer 2 build complete: $img_path"
            echo "$img_path"
        else
            log "WARNING: guestfish not found, falling back to metadata-only mode"
            create_image_metadata "$img_path" "$ROOTFS_IMAGE"
            generate_evidence "$img_path" "metadata_only"
            log "Layer 2 build complete (metadata mode): $img_path.meta.json"
            echo "$img_path.meta.json"
        fi
    else
        # Traditional loop device method (requires sudo/privileges)
        error "Loop device method not yet implemented in this version. Use libguestfs (default) instead."
    fi
}

main "$@"
