#!/usr/bin/env bash
set -Eeuo pipefail

# Layer 1: Minimal Debian Root Filesystem Builder
# Verification Class: BUILD (requires debootstrap and a Debian package mirror)
# Kernel/initramfs are resolved and installed inside the target rootfs.

# Auto-elevate to root if not already running as root.
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER1_DIR="$(dirname "$SCRIPT_DIR")"

DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
COMPONENTS="${COMPONENTS:-main,contrib,non-free-firmware}"

# Product/CLI architecture to Debian architecture. x86_64 must remain explicit.
declare -A ARCH_MAP=(
    ["x86_64"]="amd64"
    ["amd64"]="amd64"
    ["arm64"]="arm64"
    ["armhf"]="armhf"
)
declare -A KERNEL_PACKAGES=(
    ["amd64"]="linux-image-amd64"
    ["arm64"]="linux-image-arm64"
    ["armhf"]="linux-image-armmp"
)
INITRAMFS_PACKAGE="initramfs-tools"
COREUTILS_PACKAGE="coreutils"

usage() {
    cat <<EOF
Usage: $(basename "$0") <target_arch> <output_file>

Creates a Debian root filesystem with a target-resolved kernel and initramfs.

Arguments:
  target_arch   Product/Debian architecture (x86_64, amd64, arm64, armhf)
  output_file   Output path for the rootfs tarball

Environment Variables:
  DEBIAN_SUITE      Debian suite (default: bookworm)
  DEBIAN_MIRROR     Debian mirror URL (default: http://deb.debian.org/debian)
  COMPONENTS        Debian components (default: main,contrib,non-free-firmware)
EOF
    return 2
}

log() { echo "[L1-ROOTFS] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
error() { echo "[L1-ROOTFS ERROR] $*" >&2; exit 1; }

cleanup_mounts() {
    local rootfs="${1:-}"
    [[ -n "$rootfs" && -d "$rootfs" ]] || return 0
    for mountpoint in dev/pts dev sys proc; do
        mountpoint -q "$rootfs/$mountpoint" && umount -l "$rootfs/$mountpoint" || true
    done
}

check_dependencies() {
    local debian_arch="$1"
    local missing=()
    command -v debootstrap >/dev/null 2>&1 || missing+=(debootstrap)
    command -v mount >/dev/null 2>&1 || missing+=(mount)
    if [[ "$debian_arch" != "$(dpkg --print-architecture)" ]]; then
        compgen -G "/usr/bin/qemu-*-static" >/dev/null || missing+=(qemu-user-static)
    fi
    ((${#missing[@]} == 0)) || error "Missing dependencies: ${missing[*]}"
}

run_in_rootfs() {
    local rootfs="$1"
    shift
    chroot "$rootfs" "$@"
}

mount_rootfs_api() {
    local rootfs="$1"
    mount -t proc proc "$rootfs/proc"
    mount --rbind /sys "$rootfs/sys"
    mount --make-rslave "$rootfs/sys"
    mount --rbind /dev "$rootfs/dev"
    mount --make-rslave "$rootfs/dev"
}

install_x86_64_boot_marker() {
    local rootfs="$1"
    # A real oneshot unit proves userspace reached graphical.target after
    # multi-user.target, without creating an ordering cycle.
    [[ -x "$rootfs/usr/bin/printf" ]] \
        || error "Debian rootfs is missing required command: /usr/bin/printf"
    mkdir -p "$rootfs/etc/systemd/system/graphical.target.wants"
    cat > "$rootfs/etc/systemd/system/ashipaos-boot-success.service" <<'EOF'
[Unit]
Description=AshipaOS userspace boot marker
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/printf 'ASHIPAOS_BOOT_SUCCESS=1\n'
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF
    ln -s ../ashipaos-boot-success.service \
        "$rootfs/etc/systemd/system/graphical.target.wants/ashipaos-boot-success.service"
}

install_kernel_and_initramfs() {
    local rootfs="$1"
    local debian_arch="$2"
    local kernel_package="${KERNEL_PACKAGES[$debian_arch]:-}"
    [[ -n "$kernel_package" ]] || error "No kernel package policy for Debian architecture: $debian_arch"

    # Prevent package postinst scripts from starting services in the build root.
    printf '#!/bin/sh\nexit 101\n' > "$rootfs/usr/sbin/policy-rc.d"
    chmod 0755 "$rootfs/usr/sbin/policy-rc.d"
    mount_rootfs_api "$rootfs"
    trap 'cleanup_mounts "$rootfs"' RETURN

    log "Installing target kernel $kernel_package and $INITRAMFS_PACKAGE"
    run_in_rootfs "$rootfs" env DEBIAN_FRONTEND=noninteractive \
        apt-get -o DPkg::Options::=--force-confold update
    run_in_rootfs "$rootfs" env DEBIAN_FRONTEND=noninteractive \
        apt-get -y --no-install-recommends install "$kernel_package" "$INITRAMFS_PACKAGE" "$COREUTILS_PACKAGE"

    # Kernel postinst normally creates these. Explicitly finish generation so both
    # native and debootstrap --foreign builds have the same deterministic gate.
    run_in_rootfs "$rootfs" update-initramfs -u -k all
    validate_kernel_initramfs "$rootfs" "$debian_arch" "$kernel_package"

    rm -f "$rootfs/usr/sbin/policy-rc.d"
    trap - RETURN
    cleanup_mounts "$rootfs"
}

validate_kernel_initramfs() {
    local rootfs="$1"
    local debian_arch="$2"
    local kernel_package="$3"
    # Debian's package-managed entry points are root-level symlinks. Do not
    # substitute host /boot files or require non-existent /boot aliases.
    local vmlinuz="$rootfs/vmlinuz"
    local initrd="$rootfs/initrd.img"
    local vmlinuz_target initrd_target

    [[ -L "$vmlinuz" && -s "$vmlinuz" ]] || error "Missing, non-symlink, or empty $vmlinuz"
    [[ -L "$initrd" && -s "$initrd" ]] || error "Missing, non-symlink, or empty $initrd"
    vmlinuz_target=$(readlink -f "$vmlinuz")
    initrd_target=$(readlink -f "$initrd")
    [[ "$vmlinuz_target" == "$rootfs/boot/vmlinuz-"* && -s "$vmlinuz_target" ]] \
        || error "Invalid versioned kernel target: $vmlinuz_target"
    [[ "$initrd_target" == "$rootfs/boot/initrd.img-"* && -s "$initrd_target" ]] \
        || error "Invalid versioned initramfs target: $initrd_target"
    dpkg_status=$(run_in_rootfs "$rootfs" dpkg-query -W -f='${Status}' "$kernel_package" 2>/dev/null) \
        || error "Kernel package was not resolved: $kernel_package"
    [[ "$dpkg_status" == "install ok installed" ]] || error "Kernel package not installed: $kernel_package"
    dpkg_status=$(run_in_rootfs "$rootfs" dpkg-query -W -f='${Status}' "$INITRAMFS_PACKAGE" 2>/dev/null) \
        || error "Initramfs package was not resolved: $INITRAMFS_PACKAGE"
    [[ "$dpkg_status" == "install ok installed" ]] || error "Initramfs package not installed: $INITRAMFS_PACKAGE"
    log "Validated $debian_arch kernel/initramfs: $(basename "$vmlinuz_target"), $(basename "$initrd_target")"
}

create_rootfs() {
    local product_arch="$1" output_file="$2" debian_arch="$3"
    local temp_dir rootfs qemu_arch
    temp_dir=$(mktemp -d)
    rootfs="$temp_dir/rootfs"
    trap "cleanup_mounts '$rootfs'; rm -rf '$temp_dir'" EXIT
    log "Building Debian $DEBIAN_SUITE rootfs for $product_arch ($debian_arch)"

    if [[ "$debian_arch" != "$(dpkg --print-architecture)" ]]; then
        debootstrap --arch="$debian_arch" --components="$COMPONENTS" --foreign \
            "$DEBIAN_SUITE" "$rootfs" "$DEBIAN_MIRROR"
        case "$debian_arch" in
            arm64) qemu_arch=aarch64 ;;
            armhf) qemu_arch=arm ;;
            *) error "No qemu mapping for cross architecture: $debian_arch" ;;
        esac
        cp "/usr/bin/qemu-${qemu_arch}-static" "$rootfs/usr/bin/"
        chroot "$rootfs" /debootstrap/debootstrap --second-stage
        rm -f "$rootfs/usr/bin/qemu-${qemu_arch}-static"
    else
        debootstrap --arch="$debian_arch" --components="$COMPONENTS" \
            "$DEBIAN_SUITE" "$rootfs" "$DEBIAN_MIRROR"
    fi

    install_kernel_and_initramfs "$rootfs" "$debian_arch"
    if [[ "$product_arch" == "x86_64" ]]; then
        install_x86_64_boot_marker "$rootfs"
    fi
    minimize_rootfs "$rootfs"
    validate_kernel_initramfs "$rootfs" "$debian_arch" "${KERNEL_PACKAGES[$debian_arch]}"
    mkdir -p "$(dirname "$output_file")"
    tar -C "$rootfs" -czf "$output_file" .
    [[ -s "$output_file" ]] || error "Rootfs tarball is empty: $output_file"
    generate_evidence "$product_arch" "$debian_arch" "$output_file" "$rootfs"
    log "Rootfs created successfully: $output_file ($(du -h "$output_file" | cut -f1))"
}

minimize_rootfs() {
    local rootfs_dir="$1"
    find "$rootfs_dir/usr/share/doc" -type f ! -name copyright -delete 2>/dev/null || true
    find "$rootfs_dir/usr/share/man" -type f -delete 2>/dev/null || true
    find "$rootfs_dir/usr/share/info" -type f -delete 2>/dev/null || true
    rm -rf "$rootfs_dir/var/cache/apt/archives"/* "$rootfs_dir/tmp"/* "$rootfs_dir/var/tmp"/*
    find "$rootfs_dir/var/log" -type f -delete 2>/dev/null || true
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

file_metadata_json() {
    local rootfs="$1" path="$2" resolved
    resolved=$(readlink -f "$rootfs$path")
    printf '"path": "%s", "resolved_path": "%s", "size": %s, "sha256": "%s"' \
        "$path" "${resolved#"$rootfs"}" "$(stat -c %s "$resolved")" "$(sha256sum "$resolved" | cut -d' ' -f1)"
}

generate_evidence() {
    local product_arch="$1" debian_arch="$2" output_file="$3" rootfs_metadata="$4"
    local evidence_dir="$LAYER1_DIR/evidence" kernel_package="${KERNEL_PACKAGES[$debian_arch]}"
    local kernel_version initramfs_version
    kernel_version=$(run_in_rootfs "$rootfs_metadata" dpkg-query -W -f='${Version}' "$kernel_package")
    initramfs_version=$(run_in_rootfs "$rootfs_metadata" dpkg-query -W -f='${Version}' "$INITRAMFS_PACKAGE")
    mkdir -p "$evidence_dir"
    cat > "$evidence_dir/build-evidence-$(date +%Y%m%d-%H%M%S).json" <<EOF
{
  "layer": 1,
  "task": "minimal-debian-rootfs-kernel-initramfs",
  "verification_class": "BUILD",
  "timestamp": "$(date -Iseconds)",
  "parameters": {"target_arch": "$(json_escape "$product_arch")", "debian_arch": "$(json_escape "$debian_arch")", "debian_suite": "$(json_escape "$DEBIAN_SUITE")", "debian_mirror": "$(json_escape "$DEBIAN_MIRROR")"},
  "packages": {"kernel": {"name": "$(json_escape "$kernel_package")", "version": "$(json_escape "$kernel_version")"}, "initramfs": {"name": "$(json_escape "$INITRAMFS_PACKAGE")", "version": "$(json_escape "$initramfs_version")"}},
  "files": {"vmlinuz": {$(file_metadata_json "$rootfs_metadata" /vmlinuz)}, "initrd": {$(file_metadata_json "$rootfs_metadata" /initrd.img)}},
  "artefacts": {"rootfs_tarball": "$(json_escape "$output_file")", "rootfs_size": $(du -b "$output_file" | cut -f1)},
  "builder": {"architecture": "$(dpkg --print-architecture)", "debootstrap_version": "$(dpkg-query -W -f='${Version}' debootstrap 2>/dev/null || printf unknown)"}
}
EOF
    log "Evidence generated in $evidence_dir"
}

main() {
    [[ $# -eq 2 ]] || usage
    local product_arch="$1" output_file="$2"
    local debian_arch="${ARCH_MAP[$product_arch]:-}"
    [[ -n "$debian_arch" ]] || error "Invalid architecture: $product_arch (valid: x86_64, amd64, arm64, armhf)"
    check_dependencies "$debian_arch"
    create_rootfs "$product_arch" "$output_file" "$debian_arch"
    # Re-open the tarball for evidence would require extracting it; metadata was
    # captured before packaging by the same validated target rootfs.
    log "Layer 1 build completed successfully; kernel/initramfs validation passed"
}

main "$@"
