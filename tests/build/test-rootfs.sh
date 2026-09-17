#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-x86_64}"
ROOTFS="${2:-$ROOT/build/rootfs/$TARGET}"

[[ -x "$ROOTFS/bin/bash" ]] || {
  echo "Missing executable /bin/bash in $ROOTFS" >&2
  exit 1
}
[[ "$(chroot "$ROOTFS" dpkg --print-architecture)" == amd64 ]] || {
  echo "Unexpected dpkg architecture" >&2
  exit 1
}
grep -qx 'ID=debian' "$ROOTFS/etc/os-release"
grep -qx 'VERSION_CODENAME=bookworm' "$ROOTFS/etc/os-release"
grep -qx '20250906T000000Z' "$ROOTFS/etc/ashipaos-debian-snapshot"
grep -qx 'deb https://snapshot.debian.org/archive/debian/20250906T000000Z bookworm main' \
  "$ROOTFS/etc/apt/sources.list"
grep -qx 'Acquire::Check-Valid-Until "false";' \
  "$ROOTFS/etc/apt/apt.conf.d/99ashipaos-snapshot"
[[ -s "$ROOTFS/etc/ashipaos-packages.lock" ]]
KERNEL_VERSION="$(cat "$ROOTFS/etc/ashipaos-kernel-version")"
[[ -f "$ROOTFS/boot/vmlinuz-$KERNEL_VERSION" ]]
[[ -f "$ROOTFS/boot/initrd.img-$KERNEL_VERSION" ]]
chroot "$ROOTFS" id ashipaos | grep -q 'uid=1000(ashipaos)'
[[ ! -L "$ROOTFS/etc/systemd/system/multi-user.target.wants/ssh.service" ]]

assert_storage_directory() {
  local path="$1" expected="$2"
  [[ "$(stat --format='%u:%g:%a' "$ROOTFS/storage/$path")" == "$expected" ]] || {
    echo "Unexpected ownership or mode for /storage/${path:-}" >&2
    exit 1
  }
}

assert_storage_directory '' '0:0:755'
assert_storage_directory config '1000:1000:700'
assert_storage_directory state '1000:1000:700'
assert_storage_directory cache '1000:1000:755'
assert_storage_directory downloads '1000:1000:750'
assert_storage_directory thumbnails '1000:1000:755'
assert_storage_directory logs '1000:1000:750'
assert_storage_directory app '0:0:755'

echo "test-rootfs: PASS"
