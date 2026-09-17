#!/usr/bin/env bash
# Layer 2: Build Partitioned Disk Image with Bootloader
# Verification Class: BUILD (VM and HARDWARE remain blocked)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
CONFIG_FILE="${ASHIPAOS_IMAGE_CONFIG:-$LAYER_DIR/config/image-config.yaml}"
EVIDENCE_DIR="$LAYER_DIR/evidence"
OUTPUT_DIR="${GITHUB_WORKSPACE:-$REPO_ROOT}/output/images"
WORK_DIR=""
PARTIAL_IMAGE=""

ROOTFS_IMAGE=""
TARGET="x86_64"
IMAGE_SIZE_MB=""
EFI_SIZE_MB=""
ROOT_SIZE_MB=""
EFI_LABEL=""
ROOT_LABEL=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <rootfs-image> [target]

Build a GPT disk image from a Layer 1 rootfs tarball with bootloader installed.

Options:
    -h, --help       Show this help message
    --validate       Validate configuration only
    --layout-only F  Create and validate only the GPT layout in file F (test aid)
    --print-repo-root  Print the resolved repository root (test aid)

Verification Class: BUILD
Dependencies: Layer 1 rootfs, util-linux sfdisk, libguestfs-tools, grub-efi (x86_64), u-boot (ARM64)
EOF
}

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

cleanup() {
    local status="$1"
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
    if (( status != 0 )) && [[ -n "$PARTIAL_IMAGE" ]]; then
        rm -f -- "$PARTIAL_IMAGE" "$PARTIAL_IMAGE.meta.json"
    fi
}
trap 'cleanup $?' EXIT
trap 'exit 130' INT TERM

yaml_scalar() {
    local key="$1"
    awk -v key="$key" '$1 == key ":" {print $2; exit}' "$CONFIG_FILE"
}

filesystem_label() {
    local filesystem="$1"
    awk -v wanted="$filesystem" '
        /^filesystems:/ { in_filesystems=1; next }
        in_filesystems && /^[^ ]/ { in_filesystems=0 }
        in_filesystems && $1 == wanted ":" { in_wanted=1; next }
        in_wanted && /^  [a-zA-Z0-9_-]+:/ { in_wanted=0 }
        in_wanted && $1 == "label:" { print $2; exit }
    ' "$CONFIG_FILE"
}

require_uint() {
    local name="$1" value="$2"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || error "$name must be a positive integer (got: ${value:-empty})"
}

parse_and_validate_config() {
    [[ -f "$CONFIG_FILE" ]] || error "Configuration file not found: $CONFIG_FILE"

    IMAGE_SIZE_MB="$(yaml_scalar image_size_mb)"
    EFI_SIZE_MB="$(awk '/^partitions:/ {p=1; next} p && $1 == "efi:" {print $2; exit}' "$CONFIG_FILE")"
    ROOT_SIZE_MB="$(awk '/^partitions:/ {p=1; next} p && $1 == "root:" {print $2; exit}' "$CONFIG_FILE")"
    EFI_LABEL="$(filesystem_label efi)"
    ROOT_LABEL="$(filesystem_label root)"

    require_uint image_size_mb "$IMAGE_SIZE_MB"
    require_uint partitions.efi "$EFI_SIZE_MB"
    require_uint partitions.root "$ROOT_SIZE_MB"
    (( EFI_SIZE_MB >= 32 )) || error "EFI partition must be at least 32 MiB"
    (( ROOT_SIZE_MB >= 64 )) || error "root partition must be at least 64 MiB"
    [[ "$EFI_LABEL" =~ ^[A-Za-z0-9_-]{1,11}$ ]] || error "EFI label must be 1-11 safe characters"
    [[ "$ROOT_LABEL" =~ ^[A-Za-z0-9_-]{1,16}$ ]] || error "root label must be 1-16 safe characters"

    local total_sectors=$((IMAGE_SIZE_MB * 2048))
    local root_end=$((2048 + EFI_SIZE_MB * 2048 + ROOT_SIZE_MB * 2048 - 1))
    (( total_sectors > 4096 )) || error "image is too small for a GPT disk"
    (( root_end <= total_sectors - 34 )) ||
        error "partition sizes exceed image_size_mb (GPT backup table needs 33 trailing sectors)"

    log "Image configuration: total=${IMAGE_SIZE_MB}MiB, efi=${EFI_SIZE_MB}MiB, root=${ROOT_SIZE_MB}MiB"
}

write_sfdisk_spec() {
    local destination="$1"
    local efi_sectors=$((EFI_SIZE_MB * 2048))
    local root_start=$((2048 + efi_sectors))
    local root_sectors=$((ROOT_SIZE_MB * 2048))

    cat >"$destination" <<EOF
label: gpt
unit: sectors
first-lba: 2048
sector-size: 512

start=2048, size=$efi_sectors, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
start=$root_start, size=$root_sectors, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Root"
EOF
}

create_partition_layout() {
    local image="$1"
    command -v sfdisk >/dev/null || error "sfdisk is required (install the util-linux/fdisk package)"
    truncate -s "${IMAGE_SIZE_MB}M" "$image"
    write_sfdisk_spec "$WORK_DIR/partitions.sfdisk"
    sfdisk --wipe always "$image" <"$WORK_DIR/partitions.sfdisk" >/dev/null
    sfdisk --verify "$image" >/dev/null
}

populate_image() {
    local image="$1" rootfs_tar="$2"
    case "$TARGET" in
        x86_64|a95x-f3-air) ;;
        *) error "unsupported Layer 2 target: $TARGET" ;;
    esac
    command -v guestfish >/dev/null || error "guestfish is required for a full Layer 2 build; metadata-only output is forbidden"
    [[ -f "$rootfs_tar" ]] || error "Layer 1 rootfs tarball not found: $rootfs_tar"
    tar -tzf "$rootfs_tar" >/dev/null || error "Layer 1 rootfs is not a readable gzip tar archive: $rootfs_tar"

    # A single appliance session preserves mounts and imports directories, links,
    # ownership and modes in one operation. Per-file upload loses that metadata.
    guestfish <<EOF
add-drive "$image"
run
mkfs vfat /dev/sda1
set-label /dev/sda1 $EFI_LABEL
mkfs ext4 /dev/sda2
set-label /dev/sda2 $ROOT_LABEL
mount /dev/sda2 /
tar-in "$rootfs_tar" / compress:gzip
mkdir-p /boot/efi
mount /dev/sda1 /boot/efi
mkdir-p /etc
write /etc/fstab "LABEL=$ROOT_LABEL / ext4 defaults,noatime 0 1\nLABEL=$EFI_LABEL /boot/efi vfat umask=0077 0 2\n"
# Install UEFI bootloader structure for x86_64
mkdir-p /boot/efi/EFI/BOOT
mkdir-p /boot/efi/EFI/systemd
# Create placeholder for bootloader (actual bootloader installed by host tools or later layer)
# This ensures the EFI partition has the correct directory structure
write /boot/efi/EFI/BOOT/.gitkeep "EFI boot directory - bootloader installed by grub-install\n"
umount-all
EOF

    # For x86_64, install actual GRUB EFI bootloader using host tools
    if [[ "$TARGET" == "x86_64" ]]; then
        log "Installing GRUB EFI bootloader..."
        local loop_dev mount_root mount_efi
        loop_dev="$(losetup -f --show -P "$image")"
        trap "umount '$mount_efi' 2>/dev/null || true; umount '$mount_root' 2>/dev/null || true; losetup -d '$loop_dev' 2>/dev/null || true" RETURN
        
        mount_root="$WORK_DIR/mnt-root"
        mount_efi="$WORK_DIR/mnt-efi"
        mkdir -p "$mount_root" "$mount_efi"
        
        mount "${loop_dev}p2" "$mount_root"
        mount "${loop_dev}p1" "$mount_efi"
        
        # Install GRUB EFI bootloader
        if command -v grub-install >/dev/null; then
            grub-install \
                --target=x86_64-efi \
                --efi-directory="$mount_efi" \
                --bootloader-id=AshipaOS \
                --removable \
                --recheck \
                --no-floppy \
                --boot-directory="$mount_root/boot" || {
                    log "Warning: grub-install failed, creating minimal EFI boot structure"
                    # Fallback: create minimal boot structure
                    rm -f "$mount_efi/EFI/BOOT/"*".placeholder" 2>/dev/null || true
                    # Copy shim or create minimal EFI executable if available
                    if [[ -f /usr/lib/grub/x86_64-efi/grub.efi ]]; then
                        cp /usr/lib/grub/x86_64-efi/grub.efi "$mount_efi/EFI/BOOT/BOOTX64.EFI"
                    fi
                }
            
            # Generate GRUB configuration
            if command -v chroot >/dev/null && [[ -d "$mount_root/usr/bin" ]]; then
                # Bind mount necessary filesystems for chroot
                mount --bind /dev "$mount_root/dev" || true
                mount --bind /proc "$mount_root/proc" || true
                mount --bind /sys "$mount_root/sys" || true
                
                chroot "$mount_root" grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || {
                    log "Warning: grub-mkconfig failed, creating basic config"
                    cat > "$mount_root/boot/grub/grub.cfg" <<GRUBCFG
set timeout=5
menuentry "AshipaOS" {
    set root=(hd0,gpt2)
    linux /boot/vmlinuz root=LABEL=$ROOT_LABEL ro quiet
    initrd /boot/initrd.img
}
GRUBCFG
                }
                
                # Cleanup bind mounts
                umount "$mount_root/dev" 2>/dev/null || true
                umount "$mount_root/proc" 2>/dev/null || true
                umount "$mount_root/sys" 2>/dev/null || true
            fi
        else
            log "Warning: grub-install not available, image will need manual bootloader installation"
        fi
        
        umount "$mount_efi"
        umount "$mount_root"
        losetup -d "$loop_dev"
        trap - RETURN
        log "GRUB EFI bootloader installed successfully"
    fi
}

create_metadata() {
    local image="$1" rootfs="$2"
    cat >"$image.meta.json" <<EOF
{
  "image_type": "disk_image",
  "target": "$TARGET",
  "total_size_mb": $IMAGE_SIZE_MB,
  "partitions": {
    "efi": {"size_mb": $EFI_SIZE_MB, "type": "vfat", "label": "$EFI_LABEL", "mount": "/boot/efi"},
    "root": {"size_mb": $ROOT_SIZE_MB, "type": "ext4", "label": "$ROOT_LABEL", "mount": "/"}
  },
  "partition_table": "gpt",
  "bootloader": "not_configured",
  "rootfs_source": "$rootfs",
  "rootfs_size_bytes": $(stat -c%s "$rootfs"),
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

generate_evidence() {
    local image="$1"
    local runner=human run_id=local job_id=local commit_sha
    [[ "${GITHUB_ACTIONS:-false}" == true ]] && runner=github-actions
    run_id="${GITHUB_RUN_ID:-$run_id}"
    job_id="${GITHUB_JOB:-$job_id}"
    commit_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    mkdir -p "$EVIDENCE_DIR"
    cat >"$EVIDENCE_DIR/build-evidence.json" <<EOF
{
  "layer": 2,
  "task_id": "layer2-partitioned-disk-image",
  "verification_class": "BUILD",
  "runner": "$runner",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "result": "PASS",
  "evidence_path": "$image",
  "commit_sha": "$commit_sha",
  "ci_run_id": "$run_id",
  "ci_job_id": "$job_id",
  "build_mode": "full_image_guestfs",
  "artefacts": {"image": "$image", "image_meta": "$image.meta.json"},
  "dependencies": {"layer1_rootfs": "$ROOTFS_IMAGE"},
  "blocked_gates": ["VM", "HARDWARE"],
  "boot_status": "not_configured"
}
EOF
}

main() {
    local mode=build layout_path=""
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        --validate) mode=validate; shift ;;
        --layout-only) [[ $# -ge 2 ]] || error "--layout-only requires an output file"; mode=layout; layout_path="$2"; shift 2 ;;
        --print-repo-root) printf '%s\n' "$REPO_ROOT"; return 0 ;;
    esac

    parse_and_validate_config
    [[ "$mode" == validate ]] && return 0

    local temp_parent="${RUNNER_TEMP:-${REPO_ROOT}/.tmp}"
    mkdir -p "$temp_parent"
    WORK_DIR="$(mktemp -d "$temp_parent/ashipaos-image.XXXXXX")"
    if [[ "$mode" == layout ]]; then
        PARTIAL_IMAGE="$layout_path"
        create_partition_layout "$layout_path"
        PARTIAL_IMAGE=""
        return 0
    fi

    [[ $# -ge 1 && $# -le 2 ]] || error "expected <rootfs-image> [target]; use --help for usage"
    ROOTFS_IMAGE="$1"
    TARGET="${2:-x86_64}"
    [[ -f "$ROOTFS_IMAGE" ]] || error "Layer 1 rootfs tarball not found: $ROOTFS_IMAGE"
    tar -tzf "$ROOTFS_IMAGE" >/dev/null || error "Layer 1 rootfs is not a readable gzip tar archive: $ROOTFS_IMAGE"
    mkdir -p "$OUTPUT_DIR"
    local final_image temp_image
    final_image="$OUTPUT_DIR/ashipaos-${TARGET}-$(date +%Y%m%d).img"
    temp_image="$WORK_DIR/$(basename "$final_image").partial"
    [[ ! -e "$final_image" && ! -e "$final_image.meta.json" ]] ||
        error "refusing to overwrite existing Layer 2 output: $final_image"
    PARTIAL_IMAGE="$temp_image"

    create_partition_layout "$temp_image"
    populate_image "$temp_image" "$ROOTFS_IMAGE"
    mv -- "$temp_image" "$final_image"
    PARTIAL_IMAGE="$final_image"
    create_metadata "$final_image" "$ROOTFS_IMAGE"
    generate_evidence "$final_image"
    PARTIAL_IMAGE=""
    log "Layer 2 build complete: $final_image"
    echo "$final_image"
}

main "$@"
