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

BOOT_BLOBS_DIR="$LAYER_DIR/files/a95x-f3-air"
A95X_PROVENANCE="$BOOT_BLOBS_DIR/provenance.json"
A95X_BOOT_LABEL="A95XBOOT"
A95X_BOOTARGS="root=LABEL=RootFS rw console=ttyS0,115200 console=tty0"
A95X_KERNEL_SOURCE=""
A95X_INITRD_SOURCE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <rootfs-image> [target]

Build a target-specific disk image from a Layer 1 rootfs tarball with bootloader installed.

Options:
    -h, --help       Show this help message
    --validate       Validate configuration only
    --layout-only F [target]  Create and validate only the target layout in file F (test aid)
    --print-repo-root  Print the resolved repository root (test aid)

Verification Class: BUILD
Dependencies: Layer 1 rootfs, util-linux sfdisk, dosfstools (A95X FAT16), libguestfs-tools, grub-efi (x86_64), u-boot (ARM64)
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

    if [[ "$TARGET" == "a95x-f3-air" ]]; then
        [[ "$EFI_SIZE_MB" -eq 256 && "$ROOT_SIZE_MB" -eq 3584 ]] ||
            error "A95X layout requires 256 MiB boot and 3584 MiB root partitions"
        grep -qE '^      filesystem: fat16$' "$CONFIG_FILE" || error "A95X boot filesystem must be FAT16"
        grep -q 'start_sector: 8192' "$CONFIG_FILE" || error "A95X boot start sector is not recorded"
        grep -q 'start_sector: 532480' "$CONFIG_FILE" || error "A95X root start sector is not recorded"
    fi

    log "Image configuration: total=${IMAGE_SIZE_MB}MiB, efi=${EFI_SIZE_MB}MiB, root=${ROOT_SIZE_MB}MiB"
}

write_sfdisk_spec() {
    local destination="$1"
    local efi_sectors=$((EFI_SIZE_MB * 2048))
    local efi_start=2048
    [[ "$TARGET" == "a95x-f3-air" ]] && efi_start=8192
    local root_start=$((efi_start + efi_sectors))
    local root_sectors=$((ROOT_SIZE_MB * 2048))

    if [[ "$TARGET" == "a95x-f3-air" ]]; then
        # A95X SD boot uses the DOS/MBR partition table directly.  The verified
        # contract leaves sectors 1..8191 empty before the FAT16 partition.
        cat >"$destination" <<EOF
label: dos
unit: sectors
sector-size: 512

start=$efi_start, size=$efi_sectors, type=c, bootable
start=$root_start, size=$root_sectors, type=83
EOF
        return
    fi

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

    if [[ "$TARGET" == "a95x-f3-air" ]]; then
        install_a95x_boot_partition "$image" "$rootfs_tar"
        return
    fi

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

    # Install target-specific bootloader
    if [[ "$TARGET" == "x86_64" ]]; then
        install_x86_64_bootloader "$image"
    elif [[ "$TARGET" == "a95x-f3-air" ]]; then
        : # A95X boot partition is assembled before this target-specific hook.
    fi
}

make_a95x_kernel() {
    local rootfs_tar="$1" output="$2" stage="$WORK_DIR/rootfs"
    mkdir -p "$stage"

    # Layer 1 intentionally keeps Debian's /vmlinuz and /initrd.img symlinks.
    # Resolve only within the tar archive: never ask tar to follow a link or
    # extract an attacker-controlled path on the host filesystem.
    mapfile -t resolved_sources < <(python3 - "$rootfs_tar" "$stage" <<'PY'
import posixpath
import sys
import tarfile
from pathlib import Path

def archive_name(name):
    if name.startswith('/'):
        raise ValueError(f'absolute archive member: {name}')
    name = posixpath.normpath(name)
    if name in ('', '.'):
        return ''
    if name == '..' or name.startswith('../'):
        raise ValueError(f'traversal archive member: {name}')
    return name[2:] if name.startswith('./') else name

def link_target(name, target):
    # Debian's rootfs links are absolute /boot links. Permit that one
    # rootfs-internal form, but reject absolute targets elsewhere.
    if target.startswith('/') and not target.startswith('/boot/'):
        raise ValueError(f'absolute symlink target outside /boot: {name} -> {target}')
    candidate = target.lstrip('/') if target.startswith('/') else posixpath.join(posixpath.dirname(name), target)
    candidate = posixpath.normpath(candidate)
    if candidate == '..' or candidate.startswith('../'):
        raise ValueError(f'traversal symlink target: {name} -> {target}')
    return candidate

def resolve(entries, name):
    seen = set()
    current = name
    for _ in range(40):
        if current in seen:
            raise ValueError(f'symlink cycle at {name}')
        seen.add(current)
        member = entries.get(current)
        if member is None:
            raise ValueError(f'unresolved rootfs path: {name} -> {current}')
        if member.isfile():
            return current, member
        if member.issym():
            current = link_target(current, member.linkname)
            continue
        raise ValueError(f'non-regular kernel input: {current}')
    raise ValueError(f'symlink chain too deep: {name}')

archive, stage = sys.argv[1], Path(sys.argv[2])
try:
    with tarfile.open(archive, 'r:*') as tf:
        entries = {}
        for member in tf.getmembers():
            name = archive_name(member.name)
            if not name:
                continue
            if name in entries:
                raise ValueError(f'duplicate archive member: {name}')
            entries[name] = member
        with_targets = []
        for requested, output in (('vmlinuz', 'vmlinuz'), ('initrd.img', 'initrd.img')):
            source, member = resolve(entries, requested)
            stream = tf.extractfile(member)
            if stream is None:
                raise ValueError(f'cannot read regular archive member: {source}')
            destination = stage / output
            with destination.open('xb') as out:
                while True:
                    chunk = stream.read(1024 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
            with_targets.append((requested, source))
        for requested, source in with_targets:
            print(f'{requested}={source}')
except (OSError, tarfile.TarError, ValueError) as exc:
    print(f'secure rootfs extraction failed: {exc}', file=sys.stderr)
    raise SystemExit(1)
PY
) || error "A95X rootfs kernel/initramfs entries failed secure resolution"
    for source in "${resolved_sources[@]}"; do
        case "$source" in
            vmlinuz=*) A95X_KERNEL_SOURCE="${source#vmlinuz=}" ;;
            initrd.img=*) A95X_INITRD_SOURCE="${source#initrd.img=}" ;;
            *) error "unexpected secure extraction result: $source" ;;
        esac
    done
    [[ -f "$stage/vmlinuz" && -f "$stage/initrd.img" ]] ||
        error "A95X kernel inputs must be regular files inside the target rootfs"

    # Ubuntu 24.04's android-tools mkbootimg imports a missing gki module.
    # Generate the pinned legacy v0 format directly instead of trusting it.
    python3 - "$stage/vmlinuz" "$stage/initrd.img" "$output" <<'PY'
import hashlib, struct, sys
from pathlib import Path
kernel, ramdisk, out = (Path(x) for x in sys.argv[1:])
kernel_data, ramdisk_data = kernel.read_bytes(), ramdisk.read_bytes()
page = 2048
header = bytearray(608)
header[:8] = b'ANDROID!'
struct.pack_into('<10I', header, 8, len(kernel_data), 0x01080000,
                 len(ramdisk_data), 0x01000000, 0, 0x00f00000,
                 0x00000100, page, 0, 0)
# Android legacy v0 has name at [48:64], cmdline at [64:576], and the
# 20-byte ID at [576:596].
name = b'AshipaOS-A95X'
cmdline = b'root=LABEL=RootFS rw console=ttyS0,115200 console=tty0'
assert len(name) <= 16 and len(cmdline) <= 512
header[48:64] = name.ljust(16, b'\0')
header[64:576] = cmdline.ljust(512, b'\0')
header[576:596] = hashlib.sha1(kernel_data + ramdisk_data).digest()
def padded(data): return data + b'\0' * ((-len(data)) % page)
out.write_bytes(bytes(header).ljust(page, b'\0') + padded(kernel_data) + padded(ramdisk_data))
PY
    [[ "$(dd if="$output" bs=1 count=8 status=none)" == "ANDROID!" ]] ||
        error "self-contained legacy Android generator did not create a valid header"
}

make_a95x_scripts() {
    local outdir="$1"
    command -v mkimage >/dev/null || error "u-boot-tools (mkimage) is required for A95X scripts"
    cat >"$WORK_DIR/AML_AUTOSCRIPT.txt" <<'EOF'
defenv
setenv loadaddr 0x01000000
setenv dtb_mem_addr 0x10000000
setenv cfgloadsd 'fatload mmc 0:1 ${loadaddr} CFGLOAD'
setenv device mmc
setenv devnr 0
setenv partnr 1
run cfgloadsd
autoscr ${loadaddr}
EOF
    cat >"$WORK_DIR/CFGLOAD.txt" <<EOF
setenv bootargs '$A95X_BOOTARGS'
fatload \${device} \${devnr}:\${partnr} \${loadaddr} KERNEL.IMG
fatload \${device} \${devnr}:\${partnr} \${dtb_mem_addr} dtb.img
bootm \${loadaddr}
bootm start
bootm loados
bootm prep
bootm go
EOF
    mkimage -A arm64 -T script -C none -n A95X-AUTOSCRIPT -d "$WORK_DIR/AML_AUTOSCRIPT.txt" "$outdir/AML_AUTOSCRIPT" >/dev/null || error "failed to compile AML_AUTOSCRIPT"
    mkimage -A arm64 -T script -C none -n A95X-CFGLOAD -d "$WORK_DIR/CFGLOAD.txt" "$outdir/CFGLOAD" >/dev/null || error "failed to compile CFGLOAD"
}

format_a95x_boot_partition() {
    local image="$1" filesystem="$WORK_DIR/a95x-fat16.img"
    local partition_bytes=$((256 * 1024 * 1024))
    command -v mkfs.fat >/dev/null || error "dosfstools (mkfs.fat) is required for A95X FAT16 formatting"
    # The optional guestfish filesystem-formatting API is not available on all
    # CI runners. Format a bounded userspace file, then copy only the FAT16
    # partition bytes into the existing image; this cannot alter MBR geometry.
    truncate -s "$partition_bytes" "$filesystem"
    mkfs.fat -F 16 -S 512 -n "$A95X_BOOT_LABEL" "$filesystem" >/dev/null
    dd if="$filesystem" of="$image" bs=512 seek=8192 conv=notrunc status=none
}

install_a95x_boot_partition() {
    local image="$1" rootfs_tar="$2" bootdir="$WORK_DIR/a95x-boot"
    [[ -f "$A95X_PROVENANCE" ]] || error "missing exact A95X provenance manifest"
    mkdir -p "$bootdir"
    make_a95x_kernel "$rootfs_tar" "$bootdir/KERNEL.IMG"
    cp -- "$BOOT_BLOBS_DIR/meson1.dtb" "$bootdir/dtb.img"
    format_a95x_boot_partition "$image"
    make_a95x_scripts "$bootdir"
    cat >"$bootdir/manifest" <<EOF
{
  "format": "ashipaos-a95x-boot-v1",
  "target": "a95x-f3-air",
  "partition": {"table": "dos", "start_sector": 8192, "filesystem": "FAT16", "label": "$A95X_BOOT_LABEL"},
  "root_partition": {"start_sector": 532480, "filesystem": "ext4", "label": "RootFS"},
  "files": {"AML_AUTOSCRIPT": "$(sha256sum "$bootdir/AML_AUTOSCRIPT" | awk '{print $1}')", "CFGLOAD": "$(sha256sum "$bootdir/CFGLOAD" | awk '{print $1}')", "KERNEL.IMG": "$(sha256sum "$bootdir/KERNEL.IMG" | awk '{print $1}')", "dtb.img": "$(sha256sum "$bootdir/dtb.img" | awk '{print $1}')"},
  "kernel_contract": {"source": "CoreELEC 21.3-Omega inspected boot partition", "header": "ANDROID!", "page_size": 2048, "kernel_offset": "0x01080000", "ramdisk_offset": "0x01000000", "second_offset": "0x00f00000", "tags_offset": "0x00000100"},
  "rootfs_kernel_provenance": {"archive_sha256": "$(sha256sum "$rootfs_tar" | awk '{print $1}')", "kernel_entry": "/vmlinuz", "kernel_resolved": "/$A95X_KERNEL_SOURCE", "initrd_entry": "/initrd.img", "initrd_resolved": "/$A95X_INITRD_SOURCE"},
  "ddr_usb_relationship": {"file": "ddr-usb.bin", "sha256": "$(sha256sum "$BOOT_BLOBS_DIR/ddr-usb.bin" | awk '{print $1}')", "role": "matching stock USB DDR-training payload", "used_in_sd_image": false},
  "bootargs": "$A95X_BOOTARGS",
  "provenance": "layers/layer2-image/files/a95x-f3-air/provenance.json"
}
EOF
    guestfish -a "$image" <<EOF
run
set-label /dev/sda1 $A95X_BOOT_LABEL
mkfs ext4 /dev/sda2
set-label /dev/sda2 RootFS
mount /dev/sda2 /
tar-in "$rootfs_tar" / compress:gzip
mount /dev/sda1 /boot
upload $bootdir/AML_AUTOSCRIPT /boot/AML_AUTOSCRIPT
upload $bootdir/CFGLOAD /boot/CFGLOAD
upload $bootdir/KERNEL.IMG /boot/KERNEL.IMG
upload $bootdir/dtb.img /boot/dtb.img
upload $bootdir/manifest /boot/manifest
write /etc/fstab "LABEL=RootFS / ext4 defaults,noatime 0 1\n"
umount-all
EOF
}

install_x86_64_bootloader() {
    local image="$1"
    log "Installing GRUB EFI bootloader for x86_64 via guestfish..."

    local grub_efi=""
    for candidate in \
        /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
        /usr/lib/grub/x86_64-efi/grubx64.efi; do
        if [[ -f "$candidate" ]]; then
            grub_efi="$candidate"
            break
        fi
    done
    [[ -n "$grub_efi" ]] || error "GRUB EFI binary not found; install grub-efi-amd64-bin"

    # GitHub-hosted runners do not permit host loop devices or privileged
    # mounts. guestfish performs all image access through its appliance.
    guestfish -a "$image" <<EOF
run
mount /dev/sda1 /
mkdir-p /root
mount /dev/sda2 /root
mkdir-p /EFI/BOOT
mkdir-p /boot/grub
mkdir-p /root/boot/grub
upload $grub_efi /EFI/BOOT/BOOTX64.EFI
write /EFI/BOOT/grub.cfg "set timeout=5\\nmenuentry \"AshipaOS\" {\\n  set root=(hd0,gpt2)\\n  linux /vmlinuz root=LABEL=$ROOT_LABEL ro console=tty0 console=ttyS0,115200n8\\n  initrd /initrd.img\\n}\\n"
write /boot/grub/grub.cfg "set timeout=5\\nmenuentry \"AshipaOS\" {\\n  set root=(hd0,gpt2)\\n  linux /vmlinuz root=LABEL=$ROOT_LABEL ro console=tty0 console=ttyS0,115200n8\\n  initrd /initrd.img\\n}\\n"
write /root/boot/grub/grub.cfg "set timeout=5\\nmenuentry \"AshipaOS\" {\\n  set root=(hd0,gpt2)\\n  linux /vmlinuz root=LABEL=$ROOT_LABEL ro console=tty0 console=ttyS0,115200n8\\n  initrd /initrd.img\\n}\\n"
umount-all
EOF

    log "GRUB EFI bootloader installed successfully via guestfish"
}

create_metadata() {
    local image="$1" rootfs="$2" boot_type=vfat boot_label="$EFI_LABEL" boot_mount=/boot/efi
    [[ "$TARGET" == "a95x-f3-air" ]] && boot_type=fat16 && boot_label="$A95X_BOOT_LABEL" && boot_mount=/boot
    cat >"$image.meta.json" <<EOF
{
  "image_type": "disk_image",
  "target": "$TARGET",
  "total_size_mb": $IMAGE_SIZE_MB,
  "partitions": {
    "efi": {"size_mb": $EFI_SIZE_MB, "type": "$boot_type", "label": "$boot_label", "mount": "$boot_mount"},
    "root": {"size_mb": $ROOT_SIZE_MB, "type": "ext4", "label": "$ROOT_LABEL", "mount": "/"}
  },
  "partition_table": "$([[ "$TARGET" == "a95x-f3-air" ]] && echo dos || echo gpt)",
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
        --layout-only) [[ $# -ge 2 ]] || error "--layout-only requires an output file"; mode=layout; layout_path="$2"; shift 2; TARGET="${1:-x86_64}"; [[ $# -eq 0 || $# -eq 1 ]] || error "--layout-only accepts only [target]"; [[ $# -eq 0 ]] || shift ;;
        --print-repo-root) printf '%s\n' "$REPO_ROOT"; return 0 ;;
    esac

    if [[ "$mode" == "validate" ]]; then
        parse_and_validate_config
        return 0
    fi
    if [[ "$mode" == "layout" ]]; then
        parse_and_validate_config
        local temp_parent="${RUNNER_TEMP:-${REPO_ROOT}/.tmp}"
        mkdir -p "$temp_parent"
        WORK_DIR="$(mktemp -d "$temp_parent/ashipaos-image.XXXXXX")"
        PARTIAL_IMAGE="$layout_path"
        create_partition_layout "$layout_path"
        PARTIAL_IMAGE=""
        return 0
    fi

    [[ $# -ge 1 && $# -le 2 ]] || error "expected <rootfs-image> [target]; use --help for usage"
    ROOTFS_IMAGE="$1"
    TARGET="${2:-x86_64}"
    parse_and_validate_config
    [[ -f "$ROOTFS_IMAGE" ]] || error "Layer 1 rootfs tarball not found: $ROOTFS_IMAGE"
    local temp_parent="${RUNNER_TEMP:-${REPO_ROOT}/.tmp}"
    mkdir -p "$temp_parent"
    WORK_DIR="$(mktemp -d "$temp_parent/ashipaos-image.XXXXXX")"
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
