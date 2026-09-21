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
)
declare -A KERNEL_PACKAGES=(
    ["amd64"]="linux-image-amd64"
)
INITRAMFS_PACKAGE="initramfs-tools"
COREUTILS_PACKAGE="coreutils"
BUSYBOX_PACKAGE="busybox"
CA_CERTIFICATES_PACKAGE="ca-certificates"
REPO_ROOT="$(cd "$LAYER1_DIR/../.." && pwd)"
# The archive and its containing directory must remain writable by the user
# who invoked sudo so the unprivileged downstream layers can use temp files.
source "$REPO_ROOT/scripts/rootfs-ownership.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <target_arch> <output_file> [target]

Creates a Debian root filesystem with a target-resolved kernel and initramfs.

Arguments:
  target_arch   Product architecture (x86_64)
  output_file   Output path for the rootfs tarball
  target        Optional product target; enables target features from build/targets

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
    debootstrap --arch="$debian_arch" --components="$COMPONENTS" \
        "$DEBIAN_SUITE" "$rootfs" "$DEBIAN_MIRROR"

    install_kernel_and_initramfs "$rootfs" "$debian_arch"
    minimize_rootfs "$rootfs"
    validate_kernel_initramfs "$rootfs" "$debian_arch" "${KERNEL_PACKAGES[$debian_arch]}"
    mkdir -p "$(dirname "$output_file")"
    tar -C "$rootfs" \
        --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*' \
        -czf "$output_file" .
    [[ -s "$output_file" ]] || error "Rootfs tarball is empty: $output_file"
    rootfs_output_owner "$output_file" "$(dirname "$output_file")" \
        || error "Could not restore rootfs output ownership"
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
    [[ $# -ge 2 && $# -le 3 ]] || usage
    local product_arch="$1" output_file="$2"
    local debian_arch="${ARCH_MAP[$product_arch]:-}"
    [[ -n "$debian_arch" ]] || error "Invalid architecture: $product_arch (valid: x86_64, amd64)"
    check_dependencies "$debian_arch"
    create_rootfs "$product_arch" "$output_file" "$debian_arch" "${3:-}"
    # Re-open the tarball for evidence would require extracting it; metadata was
    # captured before packaging by the same validated target rootfs.
    log "Layer 1 build completed successfully; kernel/initramfs validation passed"
}

main "$@"
