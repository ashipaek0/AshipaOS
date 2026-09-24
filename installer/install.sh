#!/usr/bin/env bash
set -Eeuo pipefail
root=${INSTALLER_ROOT:-/run/ashipaos}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/installer/config.sh"
source "$ROOT_DIR/installer/partition-path.sh"
manifest=$root/appliance.img.manifest
payload=$root/appliance.img.zst
force=0; check_only=0
for arg in "$@"; do case "$arg" in --check-only) check_only=1;; ashipaos.force=1) force=1;; esac; done
[[ -r "$manifest" && -r "$payload" ]] || { printf 'installer payload missing\n' >&2; exit 1; }
read_manifest() { awk -F= -v key="$1" '$1==key {print $2; exit}' "$manifest"; }
payload_hash=$(read_manifest payload_sha256); payload_size=$(read_manifest payload_size)
image_hash=$(read_manifest image_sha256); image_size=$(read_manifest image_size)
[[ -n "$payload_hash" ]] || payload_hash=$(read_manifest sha256)
[[ -n "$payload_size" ]] || payload_size=$(read_manifest size)
[[ -n "$image_hash" ]] || image_hash=$payload_hash
[[ -n "$image_size" ]] || image_size=$payload_size
[[ "$payload_hash" =~ ^[0-9a-fA-F]{64}$ && "$payload_size" =~ ^[0-9]+$ && "$image_hash" =~ ^[0-9a-fA-F]{64}$ && "$image_size" =~ ^[0-9]+$ ]] || { printf 'invalid appliance manifest\n' >&2; exit 1; }
actual_size=$(stat -c %s "$payload"); actual_hash=$(sha256sum "$payload" | awk '{print $1}')
[[ "$actual_size" == "$payload_size" && "$actual_hash" == "$payload_hash" ]] || { printf 'appliance integrity check failed\n' >&2; exit 1; }
mount_root=${TARGET_ROOT:-}
if [[ -n "$mount_root" && "$check_only" != 1 && "${TEST_MODE:-0}" != 1 ]]; then
  printf 'TARGET_ROOT is test-only for destructive installs\n' >&2; exit 1
fi
if [[ -n "$mount_root" ]]; then
  [[ -d "$mount_root" && ! -b "$mount_root" ]] || { printf 'target root must be a mounted directory\n' >&2; exit 1; }
  marker="$mount_root/var/lib/ashipaos/install-complete"
  if (( force == 1 )) && [[ ! -e "$marker" && ! -e "$mount_root/install-complete" ]]; then printf 'force requires a valid AshipaOS completion marker\n' >&2; exit 1; fi
  if [[ -n "$mount_root" && ( -e "$marker" || -e "$mount_root/install-complete" ) ]]; then
    (( force == 1 )) || { printf 'completed appliance refused; use ashipaos.force=1\n' >&2; exit 1; }
  fi
fi
(( check_only == 1 )) && exit 0
: "${TARGET_DEVICE:?TARGET_DEVICE is required for destructive install}"
[[ -b "$TARGET_DEVICE" ]] || { [[ "${TEST_MODE:-0}" == 1 && -n "${TARGET_ROOT:-}" && -f "$TARGET_DEVICE" ]] || { printf 'production target must be a block device\n' >&2; exit 1; }; }
[[ "$TARGET_DEVICE" == /dev/* && "$TARGET_DEVICE" != /dev/*/* ]] || { [[ "${TEST_MODE:-0}" == 1 && -n "${TARGET_ROOT:-}" && -f "$TARGET_DEVICE" ]] || { printf 'invalid target device\n' >&2; exit 1; }; }
DEV_ROOT=/dev
root_partition=$(partition_path "$TARGET_DEVICE" 3)
if (( force == 1 )); then
  marker_probe=$(mktemp -d "${MARKER_TMP_ROOT:-/run}/ashipaos-marker.XXXXXX")
  mount -o ro,noload,nosuid,nodev,noexec "$root_partition" "$marker_probe" 2>/dev/null || { rm -rf "$marker_probe"; printf 'force requires a readable target partition\n' >&2; exit 1; }
  marker="$marker_probe/var/lib/ashipaos/install-complete"
  grep -qx 'installed' "$marker" || { umount "$marker_probe" 2>/dev/null || true; rm -rf "$marker_probe"; printf 'force requires a valid AshipaOS completion marker\n' >&2; exit 1; }
  umount "$marker_probe"; rm -rf "$marker_probe"
fi
# Do not mount the target read-write until the selector has completed its
# final safety revalidation and the raw image write has finished.
mount_root=${TARGET_ROOT:-}
mounted=0
cleanup() { (( mounted == 1 )) && umount "$mount_root" 2>/dev/null || true; }
trap cleanup EXIT
for tool in zstd dd stat sha256sum awk head install mount partprobe udevadm sfdisk parted e2fsck resize2fs sync mktemp rm dirname; do command -v "$tool" >/dev/null || { printf 'required runtime command missing: %s\n' "$tool" >&2; exit 1; }; done
# Re-run the complete selector policy immediately before the destructive stream.
selector_args=("ashipaos.install_target=$TARGET_DEVICE")
[[ -n "${INSTALL_SOURCE:-}" ]] && selector_args+=("ashipaos.install_source=$INSTALL_SOURCE")
(( force == 1 )) && selector_args+=(ashipaos.force=1)
if (( force == 1 )); then
  serial=/dev/ttyS0
  if [[ "${TEST_MODE:-0}" == 1 && -n "${TARGET_ROOT:-}" ]]; then serial=${INSTALL_TEST_SERIAL:-$serial}; fi
  printf 'ASHIPAOS_FORCE_REINSTALL_BEGIN\n' > "$serial"
fi
selector_script="$ROOT_DIR/installer/select-target.sh"
if [[ "${TEST_MODE:-0}" == 1 && -n "${TARGET_ROOT:-}" ]]; then selector_script=${SELECTOR_TEST_SCRIPT:-$selector_script}; fi
revalidated=$(
  INSTALL_TARGET= INSTALL_SOURCE="${INSTALL_SOURCE:-}" \
    "$selector_script" "${selector_args[@]}"
)
canonical_target=$(readlink -f -- "$TARGET_DEVICE")
canonical_revalidated=$(readlink -f -- "$revalidated")
[[ "$canonical_target" == "$canonical_revalidated" ]] || { printf 'target changed during safety recheck\n' >&2; exit 1; }
zstd -dc "$payload" | dd of="$TARGET_DEVICE" bs=4M conv=fsync status=progress
partprobe "$TARGET_DEVICE"
udevadm settle
readback=$(dd if="$TARGET_DEVICE" bs=4M count=$(( (image_size + 4194303) / 4194304 )) 2>/dev/null | head -c "$image_size" | sha256sum | awk '{print $1}')
[[ "$readback" == "$image_hash" ]] || { printf 'target verification failed\n' >&2; exit 1; }
sfdisk --dump "$TARGET_DEVICE" >/dev/null
parted -s "$TARGET_DEVICE" resizepart 3 100% || { printf 'failed to grow root partition\n' >&2; exit 1; }
partprobe "$TARGET_DEVICE" || { printf 'failed to reread partition table\n' >&2; exit 1; }
udevadm settle || { printf 'failed waiting for partition devices\n' >&2; exit 1; }
e2fsck -pf "$root_partition"
resize2fs "$root_partition"
sync
if (( mounted == 0 )); then
  mount_root=$(mktemp -d /run/ashipaos-root.XXXXXX)
  mount "$root_partition" "$mount_root"; mounted=1
fi
marker="$mount_root/var/lib/ashipaos/install-complete"
install -d -m 0755 "$(dirname "$marker")"
printf 'installed\n' > "$marker"
sync
# Unmount before rebooting: a dirty ext4 journal would be replayed (written)
# by the next boot's read-only probes, altering a disk they must not touch.
if (( mounted == 1 )); then
  umount "$mount_root" || { printf 'failed to unmount installed root\n' >&2; exit 1; }
  mounted=0
fi
sync
printf 'ASHIPAOS_INSTALL_OK\n' > /dev/ttyS0
if command -v poweroff >/dev/null && [[ "${VM_TEST:-0}" == 1 ]]; then poweroff -f; elif command -v reboot >/dev/null; then reboot -f; fi
