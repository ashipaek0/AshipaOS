#!/usr/bin/env bash
set -Eeuo pipefail
(( EUID == 0 )) || { echo 'assemble-disk-image.sh must run as root' >&2; exit 1; }
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd); source "$ROOT_DIR/installer/config.sh"; source "$ROOT_DIR/installer/partition-path.sh"
rootfs=${ROOTFS_OUT:-out/appliance-rootfs}; out=${DISK_OUT:-out/appliance.img}; tmp=$(mktemp -d); loop=
# Never delete across a mount: a failed unmount must not recurse into it.
cleanup() { set +e; umount -R "$tmp/mnt" 2>/dev/null; [[ -n "$loop" ]] && losetup -d "$loop"; rm -rf --one-file-system "$tmp"; }
trap cleanup EXIT
[[ -f "$rootfs/.sealed" ]] || { echo 'sealed rootfs required' >&2; exit 1; }
for tool in truncate parted mkfs.vfat mkfs.ext4 grub-install grub-mkconfig losetup mount umount blkid partprobe udevadm zstd stat sha256sum; do command -v "$tool" >/dev/null || { echo "$tool is required in CI" >&2; exit 1; }; done
truncate -s "$APPLIANCE_IMAGE_BYTES" "$tmp/appliance.img"
parted -s "$tmp/appliance.img" mklabel gpt mkpart BIOS 1MiB 3MiB set 1 bios_grub on mkpart ESP fat32 3MiB 515MiB set 2 esp on mkpart root ext4 515MiB 100%
loop=$(losetup --find --show --partscan "$tmp/appliance.img"); partprobe "$loop"; udevadm settle
esp=$(partition_path "$loop" 2); rootpart=$(partition_path "$loop" 3)
mkfs.vfat -n ASHIPAOS "$esp"; mkfs.ext4 -L ASHIPAOS_ROOT "$rootpart"
mkdir -p "$tmp/mnt"; mount "$rootpart" "$tmp/mnt"
cp -a "$rootfs/." "$tmp/mnt/"
root_uuid=$(blkid -s PARTUUID -o value "$rootpart"); [[ "$root_uuid" =~ ^[0-9a-fA-F-]+$ ]] || exit 1
printf 'PARTUUID=%s / ext4 defaults 0 1\n' "$root_uuid" > "$tmp/mnt/etc/fstab"
mkdir -p "$tmp/mnt/boot/efi"; mount "$esp" "$tmp/mnt/boot/efi"
cat > "$tmp/mnt/etc/default/grub" <<GRUB
GRUB_CMDLINE_LINUX_DEFAULT="quiet root=PARTUUID=$root_uuid"
# Serial as well as screen, so headless boots (CI VMs) show GRUB, kernel and
# systemd errors; tty0 stays /dev/console.
GRUB_CMDLINE_LINUX="console=ttyS0,115200 console=tty0"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
GRUB
# GRUB needs /dev, /proc and /sys in the chroot. Mount them in a private mount
# namespace: on the runner's shared propagation, host bind mounts duplicate and
# then fail to unmount; here they vanish when the namespace exits.
unshare --mount --propagation private sh -c '
  mount --bind /dev "$1/dev" &&
  mount -t proc proc "$1/proc" &&
  mount -t sysfs sysfs "$1/sys" &&
  chroot "$1" grub-install --target=i386-pc --recheck "$2" &&
  chroot "$1" grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --no-nvram --recheck &&
  chroot "$1" grub-mkconfig -o /boot/grub/grub.cfg
' _ "$tmp/mnt" "$loop"
sync
umount -R "$tmp/mnt"
mkdir -p "$(dirname "$out")"; mv "$tmp/appliance.img" "$out"
zstd -T0 -19 -f "$out" -o "${out}.zst"
size=$(stat -c %s "$out"); hash=$(sha256sum "$out" | awk '{print $1}'); payload_size=$(stat -c %s "${out}.zst"); payload_hash=$(sha256sum "${out}.zst" | awk '{print $1}')
printf 'image_sha256=%s\nimage_size=%s\npayload_sha256=%s\npayload_size=%s\n' "$hash" "$size" "$payload_hash" "$payload_size" > "${out%.img}.img.manifest"
