#!/usr/bin/env bash
set -Eeuo pipefail
out=${ISO_OUT:-out/ashipaos-installer.iso}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in out/appliance.img.zst out/appliance.img.manifest out/installer-initramfs.gz; do test -s "$f" || { echo "missing $f" >&2; exit 1; }; done
for tool in grub-mkrescue grub-mkstandalone; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }; done
kernel=${KERNEL:-out/appliance-rootfs/boot/vmlinuz-*}; kernel=$(printf '%s\n' $kernel | head -n1); test -f "$kernel"
mkdir -p "$tmp/boot/grub/i386-pc" "$tmp/install" "$tmp/EFI/BOOT"
cp "$kernel" "$tmp/boot/vmlinuz"; cp out/installer-initramfs.gz "$tmp/boot/initramfs.gz"; cp out/appliance.img.zst out/appliance.img.manifest "$tmp/install/"
cat > "$tmp/boot/grub/grub.cfg" <<'GRUB'
set timeout=3
set default=0
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry 'Install AshipaOS offline' {
 linux /boot/vmlinuz console=ttyS0,115200 console=tty0 quiet
 initrd /boot/initramfs.gz
}
menuentry 'Force reinstall AshipaOS offline' {
 linux /boot/vmlinuz console=ttyS0,115200 console=tty0 quiet ashipaos.force=1
 initrd /boot/initramfs.gz
}
GRUB
# The standalone image's root is its own memdisk, so its embedded config must
# find the installer medium first; otherwise /boot/vmlinuz is "not found".
embed=$(mktemp); trap 'rm -rf "$tmp" "$embed"' EXIT
cat > "$embed" <<'GRUB'
search --no-floppy --set=root --file /install/appliance.img.manifest
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
GRUB
grub-mkstandalone -O x86_64-efi -o "$tmp/EFI/BOOT/BOOTX64.EFI" \
  --modules='part_gpt part_msdos fat iso9660 search search_fs_file configfile normal linux efi_gop efi_uga' \
  "boot/grub/grub.cfg=$embed"
test -s "$tmp/EFI/BOOT/BOOTX64.EFI"
command -v mkfs.vfat >/dev/null || { echo 'mkfs.vfat is required' >&2; exit 1; }
esp="$tmp/efi.img"; truncate -s 16M "$esp"; mkfs.vfat "$esp" >/dev/null
command -v mcopy >/dev/null || { echo 'mtools is required' >&2; exit 1; }; mmd -i "$esp" ::EFI ::EFI/BOOT; mcopy -i "$esp" "$tmp/EFI/BOOT/BOOTX64.EFI" ::EFI/BOOT/BOOTX64.EFI
mkdir -p "$(dirname "$out")"
# grub-mkrescue creates the i386-pc and UEFI El Torito images and already
# adds the GRUB2 hybrid MBR (boot_hybrid.img) and boot-info patching. Options
# after -- reach xorriso in native command mode, where mkisofs-style flags
# such as -boot-info-table are rejected; only raise the ISO level so payload
# files over 4 GiB fit.
grub-mkrescue -o "$tmp/image.iso" "$tmp" -- -compliance iso_9660_level=3
mv "$tmp/image.iso" "$out"; sha256sum "$out" > "$out.sha256"
