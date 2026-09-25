#!/usr/bin/env bash
# Layer 1: A95X F3 Air arm64 Debian root filesystem.
# Verification Class: BUILD (CI only: debootstrap under qemu-user, Debian mirror)
#
# Produces a gzip rootfs tarball holding the target kernel, initramfs, the
# matching mainline DTB, the application runtime and the boot-status overlay.
# Layer 2 consumes the kernel/initramfs/DTB from this tarball; nothing is taken
# from the build host.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER1_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER1_DIR/../.." && pwd)"
CONFIG_FILE="$LAYER1_DIR/config/rootfs-config.yaml"
EVIDENCE_DIR="${ASHIPAOS_EVIDENCE_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output/evidence}"
SUPPORTED_TARGET="a95x-f3-air"
TARGET_FILE="$REPO_ROOT/build/targets/amlogic/boxes/$SUPPORTED_TARGET.yaml"
OVERLAY_DIR="$REPO_ROOT/rootfs-overlay"
QEMU_STATIC="/usr/bin/qemu-aarch64-static"

usage() {
    cat <<EOF
Usage: $(basename "$0") <target_arch> <output_file> [target]

Creates the $SUPPORTED_TARGET Debian arm64 root filesystem tarball.

Arguments:
  target_arch   Product architecture (arm64 only)
  output_file   Output path for the rootfs tarball (.tar.gz)
  target        Product target (default and only value: $SUPPORTED_TARGET)

Debian packages come from the snapshot.debian.org timestamp pinned in
$CONFIG_FILE; there are no mirror overrides.
EOF
}

# Logs go to stderr: several helpers return values on stdout.
log() { printf '[L1-ROOTFS] %(%Y-%m-%d %H:%M:%S)T - %s\n' -1 "$*" >&2; }
error() { printf '[L1-ROOTFS ERROR] %s\n' "$*" >&2; exit 1; }

# Validate arguments before elevating, so a usage error never prompts for sudo.
if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 2
fi
[[ "$1" == arm64 ]] || error "Invalid architecture: $1 (valid: arm64)"
[[ "${3:-$SUPPORTED_TARGET}" == "$SUPPORTED_TARGET" ]] || error "Unsupported target: $3"

if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=ASHIPAOS_EVIDENCE_DIR,GITHUB_WORKSPACE \
        bash "${BASH_SOURCE[0]}" "$@"
fi

# The archive and its directory are handed back to the sudo caller so the
# unprivileged downstream layers can read and replace it.
# shellcheck source=scripts/rootfs-ownership.sh
source "$REPO_ROOT/scripts/rootfs-ownership.sh"

OUTPUT_FILE="$2"
ROOTFS=""
TEMP_DIR=""

# Config values, all from rootfs-config.yaml and the target file.
read_config() {
    python3 - "$CONFIG_FILE" "$TARGET_FILE" <<'PY'
import re
import sys
import yaml

config = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
target = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
debian = config["debian"]
packages = [p for group in config["packages"].values() for p in group]
boot = target["mainline_boot"]
if boot["kernel_package"] not in packages:
    raise SystemExit("target kernel package is not in the rootfs package set")
snapshot = debian["snapshot"]
if not re.fullmatch(r"\d{8}T\d{6}Z", snapshot):
    raise SystemExit(f"invalid snapshot timestamp: {snapshot}")
print(debian["suite"])
print(snapshot)
print(debian["mirror"].format(snapshot=snapshot))
print(debian["security_mirror"].format(snapshot=snapshot))
print(debian["keyring"])
print(",".join(debian["components"]))
print(" ".join(packages))
print(config["hostname"])
print(config["service_user"])
print(boot["kernel_package"])
print(boot["device_tree"])
PY
}

mapfile -t CONFIG_VALUES < <(read_config)
((${#CONFIG_VALUES[@]} == 11)) || error "Could not read $CONFIG_FILE / $TARGET_FILE"
DEBIAN_SUITE="${CONFIG_VALUES[0]}"
DEBIAN_SNAPSHOT="${CONFIG_VALUES[1]}"
DEBIAN_MIRROR="${CONFIG_VALUES[2]}"
DEBIAN_SECURITY_MIRROR="${CONFIG_VALUES[3]}"
DEBIAN_KEYRING="${CONFIG_VALUES[4]}"
COMPONENTS="${CONFIG_VALUES[5]}"
read -r -a PACKAGES <<<"${CONFIG_VALUES[6]}"
HOSTNAME_VALUE="${CONFIG_VALUES[7]}"
SERVICE_USER="${CONFIG_VALUES[8]}"
KERNEL_PACKAGE="${CONFIG_VALUES[9]}"
DEVICE_TREE="${CONFIG_VALUES[10]}"

cleanup_mounts() {
    [[ -n "$ROOTFS" && -d "$ROOTFS" ]] || return 0
    local mountpoint
    for mountpoint in dev sys proc; do
        if mountpoint -q "$ROOTFS/$mountpoint"; then
            umount -R -l "$ROOTFS/$mountpoint" || true
        fi
    done
}

cleanup() {
    cleanup_mounts
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf --one-file-system -- "$TEMP_DIR"
    return 0
}
trap cleanup EXIT

check_dependencies() {
    local missing=() cmd
    for cmd in debootstrap chroot mount mountpoint python3 tar; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [[ -x "$QEMU_STATIC" ]] || missing+=(qemu-user-static)
    # Without the keyring debootstrap would skip Release signature checks.
    [[ -s "$DEBIAN_KEYRING" ]] || missing+=(debian-archive-keyring)
    python3 -c 'import yaml' 2>/dev/null || missing+=(python3-yaml)
    ((${#missing[@]} == 0)) || error "Missing dependencies: ${missing[*]}"
}

in_rootfs() {
    chroot "$ROOTFS" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"
}

mount_rootfs_api() {
    mount -t proc proc "$ROOTFS/proc"
    mount --rbind /sys "$ROOTFS/sys"
    mount --make-rslave "$ROOTFS/sys"
    mount --rbind /dev "$ROOTFS/dev"
    mount --make-rslave "$ROOTFS/dev"
}

bootstrap() {
    log "debootstrap $DEBIAN_SUITE arm64 from snapshot $DEBIAN_SNAPSHOT"
    debootstrap --arch=arm64 --components="$COMPONENTS" --foreign \
        --keyring="$DEBIAN_KEYRING" --force-check-gpg \
        "$DEBIAN_SUITE" "$ROOTFS" "$DEBIAN_MIRROR"
    # Kept for every chroot step and removed before packaging.
    install -m 0755 "$QEMU_STATIC" "$ROOTFS$QEMU_STATIC"
    chroot "$ROOTFS" /debootstrap/debootstrap --second-stage

    local components="${COMPONENTS//,/ }"
    {
        printf 'deb %s %s %s\n' "$DEBIAN_MIRROR" "$DEBIAN_SUITE" "$components"
        printf 'deb %s %s-updates %s\n' "$DEBIAN_MIRROR" "$DEBIAN_SUITE" "$components"
        printf 'deb %s %s-security %s\n' "$DEBIAN_SECURITY_MIRROR" "$DEBIAN_SUITE" "$components"
    } >"$ROOTFS/etc/apt/sources.list"
    # A snapshot's -security Release is past its Valid-Until by design; the
    # signature is still verified. snapshot.debian.org also throttles, so retry.
    cat >"$ROOTFS/etc/apt/apt.conf.d/80ashipaos-snapshot" <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::Retries "5";
EOF
}

# Leaves the chroot API filesystems mounted; main unmounts them once every
# chroot step (packages, configuration, overlay, cleanup) is done.
install_packages() {
    # Package maintainer scripts must not start services in the build root.
    printf '#!/bin/sh\nexit 101\n' >"$ROOTFS/usr/sbin/policy-rc.d"
    chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"
    mount_rootfs_api

    log "Installing: ${PACKAGES[*]}"
    in_rootfs apt-get update
    in_rootfs apt-get -y --no-install-recommends -o DPkg::Options::=--force-confold \
        install "${PACKAGES[@]}"
    # The kernel postinst and the initramfs-tools trigger generate the
    # initramfs (each run takes minutes under emulation); validate_rootfs
    # checks the result instead of regenerating it a third time.
}

configure_system() {
    if ! in_rootfs getent passwd "$SERVICE_USER" >/dev/null; then
        in_rootfs useradd --system --create-home --home-dir "/home/$SERVICE_USER" \
            --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
    fi
    # useradd leaves the password locked ("!"): a service identity, no login.

    printf '%s\n' "$HOSTNAME_VALUE" >"$ROOTFS/etc/hostname"
    printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' \
        "$HOSTNAME_VALUE" >"$ROOTFS/etc/hosts"

    # Every device must generate its own identity on first boot.
    : >"$ROOTFS/etc/machine-id"
    rm -f "$ROOTFS/var/lib/dbus/machine-id"
    # debootstrap copied the build host's resolver; use systemd-resolved instead.
    ln -sfn ../run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/network/20-wired.network" \
        "$ROOTFS/etc/systemd/network/20-wired.network"
    # Wi-Fi: iwd joins, networkd runs DHCP; credentials come from wifi.txt on
    # the boot partition (imported as a hashed PSK, then wiped from the card).
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/network/25-wireless.network" \
        "$ROOTFS/etc/systemd/network/25-wireless.network"
    install -D -m 0644 "$OVERLAY_DIR/etc/iwd/main.conf" "$ROOTFS/etc/iwd/main.conf"
    install -D -m 0755 "$OVERLAY_DIR/usr/libexec/ashipaos-wifi-import" "$ROOTFS/usr/libexec/ashipaos-wifi-import"
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/system/ashipaos-wifi-import.service" \
        "$ROOTFS/etc/systemd/system/ashipaos-wifi-import.service"
    install -D -m 0644 "$OVERLAY_DIR/usr/share/ashipaos/wifi.txt" "$ROOTFS/usr/share/ashipaos/wifi.txt"
    in_rootfs systemctl enable iwd.service ashipaos-wifi-import.service
    # IR remote: ir-keytable's udev rule loads this map when meson-ir registers.
    install -D -m 0644 "$OVERLAY_DIR/etc/rc_keymaps/a95x-f3-air.toml" "$ROOTFS/etc/rc_keymaps/a95x-f3-air.toml"
    [[ -f "$ROOTFS/etc/rc_maps.cfg" ]] || error "ir-keytable did not install /etc/rc_maps.cfg"
    sed -i '1i # AshipaOS: the A95X F3 Air IR remote on the SoC receiver.\nmeson-ir * a95x-f3-air.toml' \
        "$ROOTFS/etc/rc_maps.cfg"
    in_rootfs systemctl enable systemd-networkd.service systemd-resolved.service systemd-timesyncd.service
    # The appliance must boot with or without a network: nothing may wait for
    # one, so network-online.target is reached at once.
    ln -sfn /dev/null "$ROOTFS/etc/systemd/system/systemd-networkd-wait-online.service"

    # STORAGE partition (settings/app state, survives an OS update): grown to
    # fill the SD card on first boot, before it is ever mounted; see
    # contracts/storage.md and contracts/os-ota.md. The mount itself and its
    # fstab line (with the ordering that pulls this service in) come from
    # Layer 2 (build-image.sh), which knows the STORAGE label.
    install -D -m 0644 "$OVERLAY_DIR/usr/lib/tmpfiles.d/ashipaos-storage.conf" \
        "$ROOTFS/usr/lib/tmpfiles.d/ashipaos-storage.conf"
    install -D -m 0755 "$OVERLAY_DIR/usr/libexec/ashipaos-storage-grow" \
        "$ROOTFS/usr/libexec/ashipaos-storage-grow"
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/system/ashipaos-storage-grow.service" \
        "$ROOTFS/etc/systemd/system/ashipaos-storage-grow.service"
}

target_enables_boot_status() {
    python3 - "$TARGET_FILE" <<'PY'
import sys
import yaml
target = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if (target.get("features") or {}).get("boot_status") is True else 1)
PY
}

install_boot_status() {
    target_enables_boot_status || return 0
    local file
    for file in usr/libexec/ashipaos-boot-status-handler \
                usr/libexec/ashipaos-boot-success \
                etc/systemd/system/ashipaos-boot-status.service \
                etc/systemd/system/ashipaos-boot-success.service; do
        [[ -f "$OVERLAY_DIR/$file" ]] || error "Missing boot-status overlay file: $file"
    done
    install -D -m 0755 "$OVERLAY_DIR/usr/libexec/ashipaos-boot-status-handler" \
        "$ROOTFS/usr/libexec/ashipaos-boot-status-handler"
    # Confirms a healthy boot and clears active-root.txt's "pending" flag
    # after an OS update (contracts/os-ota.md); never touches eMMC.
    install -D -m 0755 "$OVERLAY_DIR/usr/libexec/ashipaos-boot-success" \
        "$ROOTFS/usr/libexec/ashipaos-boot-success"
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/system/ashipaos-boot-status.service" \
        "$ROOTFS/etc/systemd/system/ashipaos-boot-status.service"
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/system/ashipaos-boot-success.service" \
        "$ROOTFS/etc/systemd/system/ashipaos-boot-success.service"
    in_rootfs systemctl enable ashipaos-boot-status.service ashipaos-boot-success.service
}

# No-UART diagnostics: always installed.
install_boot_report() {
    install -D -m 0755 "$OVERLAY_DIR/usr/libexec/ashipaos-boot-report" \
        "$ROOTFS/usr/libexec/ashipaos-boot-report"
    install -D -m 0644 "$OVERLAY_DIR/etc/systemd/system/ashipaos-boot-report.service" \
        "$ROOTFS/etc/systemd/system/ashipaos-boot-report.service"
    in_rootfs systemctl enable ashipaos-boot-report.service
}

minimize_rootfs() {
    in_rootfs apt-get clean
    find "$ROOTFS/usr/share/doc" -type f ! -name copyright -delete 2>/dev/null || true
    find "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/info" -type f -delete 2>/dev/null || true
    find "$ROOTFS/var/log" -type f -delete 2>/dev/null || true
    rm -rf "$ROOTFS"/var/lib/apt/lists/* "$ROOTFS"/tmp/* "$ROOTFS"/var/tmp/*
}

# Resolves the Debian /vmlinuz and /initrd.img links (relative or absolute)
# inside the rootfs and prints: kernel-version, kernel path, initrd path.
kernel_paths() {
    local vmlinuz initrd kver
    [[ -L "$ROOTFS/vmlinuz" && -L "$ROOTFS/initrd.img" ]] || error "Missing /vmlinuz or /initrd.img symlink"
    vmlinuz="$(readlink "$ROOTFS/vmlinuz")"; vmlinuz="/${vmlinuz#/}"
    initrd="$(readlink "$ROOTFS/initrd.img")"; initrd="/${initrd#/}"
    [[ "$vmlinuz" == /boot/vmlinuz-* && -s "$ROOTFS$vmlinuz" ]] || error "Invalid kernel link target: $vmlinuz"
    [[ "$initrd" == /boot/initrd.img-* && -s "$ROOTFS$initrd" ]] || error "Invalid initramfs link target: $initrd"
    kver="${vmlinuz#/boot/vmlinuz-}"
    [[ "$initrd" == "/boot/initrd.img-$kver" ]] || error "Kernel/initramfs version mismatch: $vmlinuz $initrd"
    printf '%s\n%s\n%s\n' "$kver" "$vmlinuz" "$initrd"
}

validate_rootfs() {
    local paths kver dtb status pkg
    mapfile -t paths < <(kernel_paths)
    ((${#paths[@]} == 3)) || error "Kernel/initramfs validation failed"
    kver="${paths[0]}"
    dtb="/usr/lib/linux-image-$kver/$DEVICE_TREE"
    [[ -s "$ROOTFS$dtb" ]] || error "Kernel package does not ship the target DTB: $dtb"
    for pkg in "${PACKAGES[@]}"; do
        status="$(in_rootfs dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" || error "Package not resolved: $pkg"
        [[ "$status" == "install ok installed" ]] || error "Package not installed: $pkg ($status)"
    done
    [[ -x "$ROOTFS/usr/bin/python3" ]] || error "Rootfs lacks /usr/bin/python3"
    compgen -G "$ROOTFS/usr/lib/aarch64-linux-gnu/libmpv.so.*" >/dev/null || error "Rootfs lacks libmpv"
    [[ ! -s "$ROOTFS/etc/machine-id" ]] || error "Rootfs carries a fixed machine-id"
    log "Validated kernel $kver, initramfs, DTB $DEVICE_TREE and ${#PACKAGES[@]} packages"
    printf '%s\n%s\n%s\n%s\n' "$kver" "${paths[1]}" "${paths[2]}" "$dtb"
}

package_rootfs() {
    rm -f "$ROOTFS$QEMU_STATIC"
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    local partial="$OUTPUT_FILE.partial"
    tar -C "$ROOTFS" --numeric-owner --xattrs --acls \
        --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./run/*' \
        -czf "$partial" .
    mv -f -- "$partial" "$OUTPUT_FILE"
    [[ -s "$OUTPUT_FILE" ]] || error "Rootfs tarball is empty: $OUTPUT_FILE"
}

record_packages() {
    mkdir -p "$EVIDENCE_DIR"
    in_rootfs dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' \
        | LC_ALL=C sort >"$EVIDENCE_DIR/layer1-packages.tsv"
}

generate_evidence() {
    local kver="$1" kernel="$2" initrd="$3" dtb="$4"
    python3 - "$EVIDENCE_DIR/layer1-rootfs.json" "$ROOTFS" "$OUTPUT_FILE" "$kver" "$kernel" "$initrd" "$dtb" \
        "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$DEBIAN_MIRROR" "$DEBIAN_SECURITY_MIRROR" "$KERNEL_PACKAGE" <<'PY'
import hashlib, json, os, sys, time
out, rootfs, archive, kver, kernel, initrd, dtb, suite, snapshot, mirror, security, kernel_package = sys.argv[1:]

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def entry(path):
    real = rootfs + path
    return {"path": path, "size": os.path.getsize(real), "sha256": digest(real)}

evidence = {
    "layer": 1,
    "task": "a95x-debian-rootfs",
    "verification_class": "BUILD",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "debian": {"suite": suite, "snapshot": snapshot, "mirror": mirror, "security_mirror": security},
    "kernel": {"package": kernel_package, "version": kver,
               "vmlinuz": entry(kernel), "initrd": entry(initrd), "dtb": entry(dtb)},
    "package_manifest": "layer1-packages.tsv",
    "artefact": {"rootfs_tarball": os.path.basename(archive),
                 "size": os.path.getsize(archive), "sha256": digest(archive)},
}
with open(out, "w", encoding="utf-8") as stream:
    json.dump(evidence, stream, indent=2)
    stream.write("\n")
PY
}

main() {
    check_dependencies
    TEMP_DIR="$(mktemp -d)"
    ROOTFS="$TEMP_DIR/rootfs"
    log "Building $SUPPORTED_TARGET rootfs: Debian $DEBIAN_SUITE arm64"

    bootstrap
    install_packages
    configure_system
    install_boot_status
    install_boot_report
    minimize_rootfs
    rm -f "$ROOTFS/usr/sbin/policy-rc.d"
    cleanup_mounts

    local validated
    mapfile -t validated < <(validate_rootfs)
    ((${#validated[@]} == 4)) || error "Rootfs validation failed"
    record_packages
    package_rootfs
    generate_evidence "${validated[@]}"

    rootfs_output_owner "$OUTPUT_FILE" "$(dirname "$OUTPUT_FILE")" "$EVIDENCE_DIR" \
        "$EVIDENCE_DIR/layer1-rootfs.json" "$EVIDENCE_DIR/layer1-packages.tsv" \
        || error "Could not restore output ownership"
    log "Rootfs created: $OUTPUT_FILE ($(du -h "$OUTPUT_FILE" | cut -f1))"
}

main
