#!/usr/bin/env bash
set -Eeuo pipefail
archive=${1:?initramfs archive}; command -v gzip >/dev/null; command -v cpio >/dev/null; command -v file >/dev/null; command -v readelf >/dev/null
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
gzip -dc "$archive" | (cd "$root" && cpio -idm --quiet)
for required in init installer/discover-source.sh installer/select-target.sh installer/install.sh bin/bash usr/bin/mount usr/bin/findmnt usr/bin/blkid etc/ashipaos-runtime.commands; do
  [[ -e "$root/$required" ]] || { echo "initramfs missing $required" >&2; exit 1; }
done
# Every absolute or repository-relative shell source in the shipped scripts
# must also be present; keep this list derived rather than hand-maintained.
while IFS= read -r sourced; do
  [[ -n "$sourced" ]] || continue
  [[ -e "$root/$sourced" ]] || { echo "initramfs missing sourced helper: $sourced" >&2; exit 1; }
done < <(grep -hE '^[[:space:]]*(source|\.)[[:space:]]+"?(\$ROOT_DIR/)?installer/[A-Za-z0-9_.-]+\.sh' "$root/init" "$root/installer"/*.sh 2>/dev/null | sed -E 's/.*(installer\/[A-Za-z0-9_.-]+\.sh).*/\1/' | sort -u)
while IFS= read -r command_name; do
  [[ -n "$command_name" ]] || continue
  find "$root" -type f -o -type l | grep -Eq "/${command_name//./\\.}$" || { echo "initramfs missing runtime command: $command_name" >&2; exit 1; }
done < "$root/etc/ashipaos-runtime.commands"
[[ -x "$root/init" && -x "$root/installer/select-target.sh" && -x "$root/installer/install.sh" ]] || { echo 'initramfs executable bit missing' >&2; exit 1; }
find "$root" -type f \( -name '*.img' -o -name '*.img.zst' -o -name '*.manifest' \) -print -quit | grep -q . && { echo 'appliance payload must not be in initramfs' >&2; exit 1; }
while IFS= read -r script; do
  shebang=$(head -n1 "$script"); [[ "$shebang" == '#!'* ]] || continue
  interp=${shebang#\#!}; interp=${interp%% *}; [[ "$interp" == /* ]] || continue
  [[ -x "$root$interp" ]] || { echo "missing script interpreter $interp" >&2; exit 1; }
done < <(find "$root" -type f -perm /111)
while IFS= read -r elf; do
  interp=$(readelf -l "$elf" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' | tr -d ' ' || true)
  [[ -z "$interp" || -e "$root$interp" ]] || { echo "missing ELF interpreter $interp" >&2; exit 1; }
  while read -r lib; do [[ -z "$lib" || -n "$(find "$root" -type f -name "$lib" -print -quit)" ]] || { echo "missing ELF dependency $lib" >&2; exit 1; }; done < <(readelf -d "$elf" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
done < <(find "$root" -type f -print0 | xargs -0 file 2>/dev/null | awk -F: '/ELF/{print $1}')
kernel_versions=("$root"/lib/modules/*)
(( ${#kernel_versions[@]} == 1 )) || { echo 'expected one initramfs kernel tree' >&2; exit 1; }
kernel=${kernel_versions[0]##*/}
for module in virtio_pci virtio_blk sr_mod isofs ext4 nvme ahci libahci ata_piix sd_mod usb_storage uas xhci_pci; do
  module_file=$(modinfo -b "$root" -k "$kernel" -n "$module" 2>/dev/null || true)
  if [[ "$module_file" == '(builtin)' ]]; then
    grep -Eq "/(${module//_/-}|${module})\.ko$" "$root/lib/modules/$kernel/modules.builtin" || { echo "missing builtin kernel module $module" >&2; exit 1; }
    continue
  fi
  [[ "$module_file" != "$root"/* ]] || module_file=${module_file#"$root"}
  module_file="${module_file#/}"; module_file="/${module_file#/}"
  [[ "$module_file" == /lib/modules/"$kernel"/* && -f "$root$module_file" ]] || { echo "missing kernel module $module" >&2; exit 1; }
done
for metadata in modules.dep modules.alias modules.builtin; do find "$root/lib/modules" -type f -name "$metadata" -print -quit | grep -q . || { echo "missing module metadata $metadata" >&2; exit 1; }; done
printf '%s\n' 'initramfs runtime closure: PASS'