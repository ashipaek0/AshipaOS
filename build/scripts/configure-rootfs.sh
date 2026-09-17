#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-}"
ROOTFS="${2:-$ROOT/build/rootfs/${TARGET:-missing}}"
MOUNTS=()

cleanup() {
  set +e
  for ((i=${#MOUNTS[@]}-1; i>=0; i--)); do
    umount -l "${MOUNTS[$i]}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

[[ "$TARGET" == x86_64 ]] || {
  echo "configure-rootfs currently supports only x86_64" >&2
  exit 2
}
[[ "$(id -u)" -eq 0 && -x "$ROOTFS/bin/bash" ]] || {
  echo "Run as root with a bootstrapped rootfs" >&2
  exit 1
}

mapfile -t PACKAGES < <(sed -n 's/^  - //p' "$ROOT/build/config/packages.lock")
[[ ${#PACKAGES[@]} -gt 0 ]] || {
  echo "No packages declared in packages.lock" >&2
  exit 1
}

for filesystem in proc sys dev; do
  mount --rbind "/$filesystem" "$ROOTFS/$filesystem"
  mount --make-rslave "$ROOTFS/$filesystem"
  MOUNTS+=("$ROOTFS/$filesystem")
done

cp --dereference /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "${PACKAGES[@]}"
chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists"/*

chroot "$ROOTFS" groupadd --force render
chroot "$ROOTFS" groupadd --force input
chroot "$ROOTFS" groupadd --force video
if ! chroot "$ROOTFS" id ashipaos >/dev/null 2>&1; then
  chroot "$ROOTFS" useradd --uid 1000 --create-home --shell /usr/sbin/nologin \
    --groups audio,input,render,video ashipaos
fi

rsync -aHAX "$ROOT/rootfs-overlay/" "$ROOTFS/"
# Do not ask systemd-tmpfiles to traverse from the host-owned workspace into
# the rootfs. It correctly rejects that ownership transition as unsafe on CI.
# Provision the declared storage layout directly, using numeric image owners.
install -d -o 0 -g 0 -m 0755 "$ROOTFS/storage"
install -d -o 1000 -g 1000 -m 0700 \
  "$ROOTFS/storage/config" "$ROOTFS/storage/state"
install -d -o 1000 -g 1000 -m 0755 \
  "$ROOTFS/storage/cache" "$ROOTFS/storage/thumbnails"
install -d -o 1000 -g 1000 -m 0750 \
  "$ROOTFS/storage/downloads" "$ROOTFS/storage/logs"
install -d -o 0 -g 0 -m 0755 "$ROOTFS/storage/app"
chroot "$ROOTFS" systemctl enable \
  connman.service nftables.service systemd-timesyncd.service \
  ashipaos-storage.service ashipaos-display.service
chroot "$ROOTFS" systemctl disable ssh.service 2>/dev/null || true

: >"$ROOTFS/etc/machine-id"
ln -sfn /proc/self/mounts "$ROOTFS/etc/mtab"
# The format expression is interpreted by dpkg-query inside the chroot.
# shellcheck disable=SC2016
chroot "$ROOTFS" dpkg-query --show \
  --showformat='${binary:Package}\t${Version}\t${Architecture}\n' \
  | LC_ALL=C sort >"$ROOTFS/etc/ashipaos-packages.lock"

KERNEL_VERSION="$(find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | LC_ALL=C sort -V | tail -1)"
[[ -n "$KERNEL_VERSION" && -f "$ROOTFS/boot/initrd.img-$KERNEL_VERSION" ]] || {
  echo "Pinned kernel package did not produce a complete boot bundle" >&2
  exit 1
}
printf '%s\n' "$KERNEL_VERSION" >"$ROOTFS/etc/ashipaos-kernel-version"
echo "Configured $TARGET rootfs with kernel $KERNEL_VERSION"
