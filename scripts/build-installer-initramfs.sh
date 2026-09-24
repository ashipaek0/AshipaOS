#!/usr/bin/env bash
set -Eeuo pipefail
rootfs=${ROOTFS_OUT:-out/appliance-rootfs}; out=${INITRAMFS_OUT:-out/installer-initramfs.gz}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
command -v cpio >/dev/null || { echo 'cpio is required' >&2; exit 1; }
command -v gzip >/dev/null || { echo 'gzip is required' >&2; exit 1; }
command -v file >/dev/null || { echo 'file is required' >&2; exit 1; }
command -v ldd >/dev/null || { echo 'ldd is required' >&2; exit 1; }
mkdir -p "$tmp"/{bin,dev,proc,sys,run,installer,usr/bin,usr/lib,lib,lib64,etc/modprobe.d,etc}
copy_runtime() {
  local src=$1 dst="$tmp$1" lib line
  [[ -e "$src" || -L "$src" ]] || { echo "missing initramfs runtime: $src" >&2; exit 1; }
  mkdir -p "$(dirname "$dst")"; cp -aL "$src" "$dst"
  if file "$src" 2>/dev/null | grep -q 'dynamically linked'; then
    # ldd prints the ELF interpreter as a bare /lib... line, not an => entry.
    interp=$(readelf -l "$src" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | tr -d ' ' || true)
    if [[ -n "${interp:-}" && -e "$interp" ]]; then mkdir -p "$tmp$(dirname "$interp")"; cp -aL "$interp" "$tmp$interp"; fi
    while read -r line; do
      lib=${line##*=> }; lib=${lib%% (*}
      [[ "$lib" == /* && -e "$lib" ]] || continue
      mkdir -p "$tmp$(dirname "$lib")"; cp -aL "$lib" "$tmp$lib"
    done < <(ldd "$src" 2>/dev/null || true)
  fi
}
runtime_commands=(bash env mount umount switch_root zstd dd stat sha256sum awk head install readlink sed cat sync sfdisk sgdisk parted flock grep find findmnt blkid lsblk e2fsck resize2fs partprobe udevadm modprobe pvs dmsetup mdadm reboot poweroff mktemp rm rmdir dirname mkdir readelf)
for cmd in "${runtime_commands[@]}"; do
  src=$(command -v "$cmd" || true)
  [[ -n "$src" ]] || { echo "missing initramfs runtime command: $cmd" >&2; exit 1; }
  copy_runtime "$src"
done
printf '%s\n' "${runtime_commands[@]}" > "$tmp/etc/ashipaos-runtime.commands"
[[ -d "$rootfs/lib/modules" ]] || { echo 'rootfs kernel modules are required' >&2; exit 1; }
rootfs=$(readlink -f "$rootfs")
cp -a "$rootfs/lib/modules" "$tmp/lib/"
kernel_versions=("$rootfs"/lib/modules/*)
(( ${#kernel_versions[@]} == 1 )) || { echo 'expected one target kernel module tree' >&2; exit 1; }
kernel=${kernel_versions[0]##*/}
for module in virtio_pci virtio_blk sr_mod isofs ext4 nvme ahci libahci sd_mod usb_storage uas xhci_pci; do
  module_file=$(modinfo -b "$rootfs" -k "$kernel" -n "$module" 2>/dev/null || true)
  if [[ "$module_file" == '(builtin)' ]]; then
    grep -Eq "/(${module//_/-}|${module})\.ko$" "$tmp/lib/modules/$kernel/modules.builtin" || { echo "builtin module missing from target metadata: $module" >&2; exit 1; }
    continue
  fi
  [[ "$module_file" != "$rootfs"/* ]] || module_file=${module_file#"$rootfs"}
  module_file="${module_file#/}"; module_file="/${module_file#/}"
  [[ "$module_file" == /lib/modules/"$kernel"/* && -f "$tmp$module_file" ]] || { echo "required hardware module missing: $module" >&2; exit 1; }
done
cp -aL "$(command -v bash)" "$tmp/bin/bash"
cat > "$tmp/etc/modprobe.d/ashipaos.conf" <<'CONF'
# Installer storage/filesystem drivers are intentionally present and loaded.
CONF
cp installer/config.sh installer/partition-path.sh installer/discover-source.sh installer/select-target.sh installer/install.sh "$tmp/installer/"

cat > "$tmp/init" <<'INIT'
#!/bin/bash
set -Eeuo pipefail
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
udevadm trigger --action=add || true
udevadm settle --timeout=20 || { echo "udev did not settle" >&2; exit 1; }
essential_modules=(virtio_pci virtio_blk sr_mod isofs ext4)
optional_modules=(nvme ahci libahci sd_mod usb-storage uas xhci-pci)
for module in "${essential_modules[@]}"; do modprobe "$module" || { echo "essential module failed: $module" >&2; exit 1; }; done
for module in "${optional_modules[@]}"; do modprobe "$module" 2>/dev/null || echo "optional module unavailable: $module" >&2; done
udevadm trigger --action=add || { echo 'post-module device trigger failed' >&2; exit 1; }
udevadm settle --timeout=30 || { echo 'post-module devices did not settle' >&2; exit 1; }
compgen -G '/dev/sr*' >/dev/null || compgen -G '/dev/sd*' >/dev/null || compgen -G '/dev/nvme*n*' >/dev/null || compgen -G '/dev/mmcblk*' >/dev/null || { echo 'no installer media block device after module loading' >&2; exit 1; }
mkdir -p /run/ashipaos /run/iso
# Discover and verify the actual optical or installer medium.
cmdline=$(cat /proc/cmdline)
source_arg=
for arg in $cmdline; do case "$arg" in ashipaos.install_source=*) source_arg=${arg#*=};; esac; done
source=$(
  INSTALL_SOURCE="$source_arg" SOURCE_MOUNT=/run/iso \
    /installer/discover-source.sh 2>/run/ashipaos/source.err || true
)
[[ -n "$source" ]] || { echo 'installer source medium missing verified payload/manifest' >&2; printf 'ASHIPAOS_INSTALL_REFUSED_SOURCE\n' > /dev/ttyS0; exec /usr/bin/env bash; }
[[ -b "$source" && -s /run/iso/install/appliance.img.zst && -s /run/iso/install/appliance.img.manifest ]] || { echo 'source discovery returned no qualified mounted media' >&2; exit 1; }
for arg in $cmdline; do case "$arg" in ashipaos.install_target=*|ashipaos.install_source=*|ashipaos.force=1|ashipaos.vm_test=1) set -- "$@" "$arg";; esac; done
case " $cmdline " in *' ashipaos.vm_test=1 '*) export VM_TEST=1;; esac
export INSTALL_SOURCE="$source" INSTALLER_ROOT=/run/iso/install
if target=$(/installer/select-target.sh "$@" 2>/run/ashipaos/selector.err); then
  [[ -b "$target" ]] || { echo 'target selector returned no destination block device' >&2; exit 1; }
  TARGET_DEVICE="$target" /installer/install.sh "$@" || exec /usr/bin/env bash
else
  cat /run/ashipaos/selector.err >&2
  if grep -q '^ASHIPAOS_INSTALL_REFUSED_MARKER$' /run/ashipaos/selector.err; then
    printf 'ASHIPAOS_INSTALL_REFUSED_MARKER\n' > /dev/ttyS0
  else
    printf 'ASHIPAOS_INSTALL_REFUSED_UNSAFE\n' > /dev/ttyS0
  fi
  exec /usr/bin/env bash
fi
INIT
chmod +x "$tmp/init"
(cd "$tmp" && find . -print0 | sort -z | cpio --null -o -H newc) | gzip -9 > "$out"
