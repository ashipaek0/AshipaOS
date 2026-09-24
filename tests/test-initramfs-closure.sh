#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); mode=${1:?mode}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tree/installer" "$tmp/tree/bin" "$tmp/tree/usr/bin" "$tmp/tree/etc" "$tmp/tree/lib/modules/test/kernel" "$tmp/bin"
cat > "$tmp/tree/init" <<'SH'
#!/bin/bash
source "$ROOT_DIR/installer/config.sh"
. "$ROOT_DIR/installer/partition-path.sh"
SH
printf '#!/bin/bash\nsource "$ROOT_DIR/installer/new-helper.sh"\n' > "$tmp/tree/installer/install.sh"
printf '#!/bin/bash\n' > "$tmp/tree/installer/select-target.sh"
printf 'data\n' > "$tmp/tree/installer/config.sh"
printf 'data\n' > "$tmp/tree/installer/partition-path.sh"
printf 'data\n' > "$tmp/tree/installer/new-helper.sh"
printf 'data\n' > "$tmp/tree/installer/discover-source.sh"
printf '#!/bin/bash\n' > "$tmp/tree/bin/bash"
ln -s bash "$tmp/tree/bin/sh"
printf '#!/bin/bash\n' > "$tmp/tree/usr/bin/mount"
printf '#!/bin/bash\n' > "$tmp/tree/usr/bin/findmnt"
printf '#!/bin/bash\n' > "$tmp/tree/usr/bin/blkid"
printf '#!/bin/bash\n' > "$tmp/tree/usr/bin/rmdir"
chmod +x "$tmp/tree/init" "$tmp/tree/bin/bash" "$tmp/tree/usr/bin/"* "$tmp/tree/installer/"*.sh
printf 'rmdir\n' > "$tmp/tree/etc/ashipaos-runtime.commands"
for mod in virtio_pci virtio_blk sr_mod isofs ext4 nvme ahci libahci ata_piix sd_mod usb_storage uas xhci_pci; do
  case "$mod" in usb_storage) file=usb-storage;; xhci_pci) file=xhci-pci;; *) file=$mod;; esac
  printf 'module\n' > "$tmp/tree/lib/modules/test/kernel/$file.ko.zst"
done
for f in modules.dep modules.alias modules.builtin; do : > "$tmp/tree/lib/modules/test/$f"; done
cat > "$tmp/bin/modinfo" <<'SH'
#!/bin/bash
case "$6" in usb_storage) file=usb-storage;; xhci_pci) file=xhci-pci;; *) file=$6;; esac
printf '%s/lib/modules/test/kernel/%s.ko.zst\n' "$2" "$file"
SH
chmod +x "$tmp/bin/modinfo"
pack() { (cd "$tmp/tree" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$tmp/initrd.gz"); }
case "$mode" in
 positive) :;;
 missing-helper) rm "$tmp/tree/installer/new-helper.sh";;
 missing-command) rm "$tmp/tree/usr/bin/rmdir";;
 missing-hyphen-module) rm "$tmp/tree/lib/modules/test/kernel/usb-storage.ko.zst";;
 missing-xhci-module) rm "$tmp/tree/lib/modules/test/kernel/xhci-pci.ko.zst";;
 *) exit 2;;
esac
pack
if [[ "$mode" == positive ]]; then
  PATH="$tmp/bin:$PATH" "$root/scripts/check-initramfs-closure.sh" "$tmp/initrd.gz"
else
  if PATH="$tmp/bin:$PATH" "$root/scripts/check-initramfs-closure.sh" "$tmp/initrd.gz" > "$tmp/output" 2>&1; then
    echo "closure unexpectedly passed: $mode" >&2; exit 1
  fi
  case "$mode" in
    missing-helper) grep -Fxq 'initramfs missing sourced helper: installer/new-helper.sh' "$tmp/output";;
    missing-command) grep -Fxq 'initramfs missing runtime command: rmdir' "$tmp/output";;
    missing-hyphen-module) grep -Fxq 'missing kernel module usb_storage' "$tmp/output";;
    missing-xhci-module) grep -Fxq 'missing kernel module xhci_pci' "$tmp/output";;
  esac
fi
