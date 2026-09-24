#!/usr/bin/env bash
set -Eeuo pipefail
# Print exactly one safe whole-disk device, or fail closed.
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/installer/config.sh"
source "$ROOT_DIR/installer/partition-path.sh"
sysfs=${SYSFS_ROOT:-/sys}; devroot=${DEV_ROOT:-/dev}; export DEV_ROOT="$devroot"; explicit=${INSTALL_TARGET:-}; source=${INSTALL_SOURCE:-}; force=0; fixture=0
for arg in "$@"; do
  case "$arg" in
    ashipaos.install_target=*) explicit=${arg#*=};;
    ashipaos.install_source=*) source=${arg#*=};;
    ashipaos.force=1) force=1;;
    --fixture-root) fixture=1;;
  esac
done
# Synthetic trees are test-only and cannot be enabled accidentally in production.
if [[ "$devroot" != /dev || "$sysfs" != /sys ]]; then
  (( fixture == 1 )) || { printf 'fixture storage roots require --fixture-root\n' >&2; exit 1; }
fi
canonical() { readlink -f -- "$1" 2>/dev/null || true; }
ancestor_name() {
  local p n; p=$(canonical "$1"); n=${p##*/}
  [[ "$n" =~ ^(nvme[0-9]+n[0-9]+|mmcblk[0-9]+)p[0-9]+$ ]] && { printf '%s\n' "${BASH_REMATCH[1]}"; return; }
  [[ "$n" =~ ^(.+[^0-9])[0-9]+$ ]] && { printf '%s\n' "${BASH_REMATCH[1]}"; return; }
  printf '%s\n' "$n"
}
source_name=${source##*/}; source_disk=$(ancestor_name "$source")
if [[ "$source" == /dev/* ]] && command -v lsblk >/dev/null; then
  parent=$(lsblk -ndo PKNAME -- "$source" 2>/dev/null || true)
  [[ -z "$parent" ]] || source_disk=${parent##*/}
fi
completed_layout_valid() {
  local disk=$1 p2 p3 p1 name kind expected n count=0
  p1=$(partition_path "$disk" 1); p2=$(partition_path "$disk" 2); p3=$(partition_path "$disk" 3)
  if (( fixture )); then [[ -e "$p1" && -e "$p2" && -e "$p3" ]] || return 1
  else [[ -b "$p1" && -b "$p2" && -b "$p3" ]] || return 1; fi
  command -v lsblk >/dev/null || return 1
  local seen1=0 seen2=0 seen3=0
  while read -r name kind; do
    [[ -z "$name" ]] && continue
    [[ "$kind" == part ]] || return 1
    expected=''
    for n in 1 2 3; do [[ "$(canonical "$devroot/$name")" == "$(canonical "$(partition_path "$disk" "$n")")" ]] && expected=$n; done
    [[ -n "$expected" ]] || return 1
    case "$expected" in
      1) (( seen1 == 0 )) || return 1; seen1=1;;
      2) (( seen2 == 0 )) || return 1; seen2=1;;
      3) (( seen3 == 0 )) || return 1; seen3=1;;
    esac
    count=$((count+1))
  done < <(lsblk -nr -o NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"')
  (( seen1 == 1 && seen2 == 1 && seen3 == 1 && count == 3 )) || return 1
  command -v blkid >/dev/null || return 1
  [[ "$(blkid -s LABEL -o value "$p2" 2>/dev/null || true)" == ASHIPAOS ]] || return 1
  [[ "$(blkid -s LABEL -o value "$p3" 2>/dev/null || true)" == ASHIPAOS_ROOT ]] || return 1
  [[ -z "$(blkid -s LABEL -o value "$(partition_path "$disk" 1)" 2>/dev/null || true)" ]] || return 1
}
marker_invalid=0; marker_checked=0
marker_valid() {
  local disk=$1 mnt marker part result=1
  if (( fixture )) && [[ -n "${FIXTURE_MARKER_ROOT:-}" ]]; then
    marker=${FIXTURE_MARKER_ROOT%/}/var/lib/ashipaos/install-complete
    [[ -f "$marker" ]] && grep -qx 'installed' "$marker" || return 1
    # Fixture force paths still model the exact three-partition product layout.
    local fixture_child fixture_name
    for fixture_child in "$sysfs/block/${disk##*/}"/*; do
      [[ -e "$fixture_child" ]] || continue
      fixture_name=${fixture_child##*/}
      case "$fixture_name" in "${disk##*/}1"|"${disk##*/}2"|"${disk##*/}3"|holders|attrs) : ;; *) return 1 ;; esac
    done
    [[ -e "$sysfs/block/${disk##*/}/${disk##*/}1" && -e "$sysfs/block/${disk##*/}/${disk##*/}2" && -e "$sysfs/block/${disk##*/}/${disk##*/}3" ]] || return 1
    return
  fi
  command -v mount >/dev/null || return 1
  part=$(partition_path "$disk" 3)
  mnt=$(mktemp -d "${MARKER_TMP_ROOT:-/run}/ashipaos-marker.XXXXXX" 2>/dev/null || return 1)
  if { [[ -b "$part" ]] || (( fixture )) && [[ -e "$part" ]]; } && mount -o ro,noload,nosuid,nodev,noexec "$part" "$mnt" 2>/dev/null; then
    marker_checked=1
    marker="$mnt/var/lib/ashipaos/install-complete"
    if [[ -f "$marker" ]] && grep -qx 'installed' "$marker" && completed_layout_valid "$disk"; then result=0; else marker_invalid=1; fi
    umount "$mnt" 2>/dev/null || result=1
  fi
  rmdir "$mnt" 2>/dev/null || true
  return "$result"
}
is_safe() {
  local path=$1 name=${1##*/} base="$sysfs/block/${1##*/}" size removable ro loop=0 ram=0 marker_ok=0
  [[ -e "$path" && -e "$base" ]] || return 1
  (( fixture == 1 )) || [[ -b "$path" ]] || return 1
  if [[ -f "$base/attrs" ]]; then { read -r size; read -r removable; read -r ro; read -r _; } < "$base/attrs"; else
    size=$(($(<"$base/size") * 512)); removable=$(<"$base/removable"); ro=$(<"$base/ro"); [[ -e "$base/device" ]] || return 1
    [[ -e "$base/loop" ]] && loop=1; [[ -e "$base/ram" ]] && ram=1
  fi
  [[ "$size" =~ ^[0-9]+$ ]] && (( size >= MIN_INSTALL_DISK_BYTES )) || return 1
  [[ ${removable:-1} == 0 && ${ro:-1} == 0 && $loop == 0 && $ram == 0 ]] || return 1
  [[ "$name" != sr* && "$name" != loop* && "$name" != ram* && "$name" != fd* ]] || return 1
  [[ "$name" != "$source_name" && "$name" != "$source_disk" ]] || return 1
  local child kind canonical_child sysnode signature fstype label parttype expected_parttype
  local -a descendants=()
  if (( fixture )) && [[ "${SELECTOR_PRODUCTION_PROBES:-0}" != 1 ]]; then
    descendants+=("$path")
    for child in "$base"/"$name"*; do [[ ! -e "$child" ]] || descendants+=("$devroot/${child##*/}"); done
  else
    command -v lsblk >/dev/null || return 1
    while read -r child kind; do
      [[ "$kind" == disk || "$kind" == part ]] || return 1
      [[ -n "$child" ]] && descendants+=("$(canonical "$child")")
    done < <(lsblk -nrpo NAME,TYPE "$path" 2>/dev/null)
    [[ ${descendants[0]:-} == "$path" ]] || return 1
  fi
  if (( ${#descendants[@]} > 1 )); then
    if marker_valid "$path"; then
      if (( force == 1 )); then marker_ok=1; else marker_invalid=1; return 1; fi
    fi
  fi
  (( ${#descendants[@]} == 1 || marker_ok == 1 )) || return 1
  local -a mounts=() swaps=()
  local mount_output mount_status
  mount_output=$(findmnt -rn -o SOURCE 2>/dev/null) && mount_status=0 || mount_status=$?
  (( mount_status == 0 )) || return 1
  mapfile -t mounts <<< "$mount_output"
  mapfile -t swaps < <(awk 'NR>1 {print $1}' "${SWAPS_FILE:-/proc/swaps}" 2>/dev/null || true)
  for child in "${descendants[@]}"; do
    [[ -n "$child" && "$child" == "$devroot/"* ]] || return 1
    canonical_child=$(canonical "$child"); [[ "$canonical_child" == "$child" ]] || return 1
    for signature in "${mounts[@]}" "${swaps[@]}"; do
      # findmnt may report a bind mount as /dev/disk[/subdirectory]. Compare
      # the canonical backing device, never a textual prefix.
      signature=${signature%%\[*}
      [[ -n "$signature" ]] || continue
      [[ "$(canonical "$signature")" != "$child" ]] || return 1
    done
    sysnode="$base"; [[ "$child" == "$path" ]] || sysnode="$base/${child##*/}"
    [[ ! -d "$sysnode/holders" || -z "$(find "$sysnode/holders" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]] || return 1
    if command -v pvs >/dev/null && pvs --noheadings -o pv_name "$child" 2>/dev/null | grep -q .; then return 1; fi
    # Plain `mdadm --examine` also succeeds on any partition table (it reports
    # the protective MBR), so only an exported md superblock means RAID.
    if command -v mdadm >/dev/null && [[ "$(mdadm --examine --export "$child" 2>/dev/null || true)" == *MD_UUID=* ]]; then return 1; fi
    if command -v dmsetup >/dev/null && dmsetup info "$child" >/dev/null 2>&1; then return 1; fi
    signature=$(blkid -p -o export "$child" 2>/dev/null || true)
    if (( marker_ok == 0 )); then [[ -z "$signature" ]] || return 1; continue; fi
    if [[ "$child" == "$path" ]]; then
      [[ "$signature" == *$'PTTYPE=gpt'* ]] || return 1
      while IFS= read -r line; do
        [[ "$line" == PTTYPE=gpt || "$line" == PTUUID=* || "$line" == DEVNAME=* ]] || return 1
      done <<< "$signature"
      continue
    fi
    fstype=$(printf '%s\n' "$signature" | awk -F= '$1=="TYPE"{print $2}')
    label=$(printf '%s\n' "$signature" | awk -F= '$1=="LABEL"{print $2}')
    case "$child" in
      "$(partition_path "$path" 1)") [[ -z "$fstype" && -z "$label" ]] || return 1; expected_parttype=21686148-6449-6e6f-744e-656564454649;;
      "$(partition_path "$path" 2)") [[ "$fstype" == vfat && "$label" == ASHIPAOS ]] || return 1; expected_parttype=c12a7328-f81f-11d2-ba4b-00a0c93ec93b;;
      "$(partition_path "$path" 3)") [[ "$fstype" == ext4 && "$label" == ASHIPAOS_ROOT ]] || return 1; expected_parttype=0fc63daf-8483-4772-8e79-3d69d8477de4;;
      *) return 1;;
    esac
    parttype=$(lsblk -nro PARTTYPE "$child" 2>/dev/null || true)
    [[ "${parttype,,}" == "$expected_parttype" ]] || return 1
    [[ "$signature" != *'LVM2_member'* && "$signature" != *'linux_raid_member'* && "$signature" != *'crypto_LUKS'* ]] || return 1
    [[ "$signature" != *$'USAGE=raid'* && "$signature" != *$'USAGE=crypto'* ]] || return 1
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == DEVNAME=* || "$line" == UUID=* || "$line" == PARTUUID=* || "$line" == PART_ENTRY_* || "$line" == BLOCK_SIZE=* || "$line" == VERSION=* || "$line" == USAGE=* || "$line" == LABEL=* || "$line" == TYPE=* ]] || return 1
    done <<< "$signature"
  done
  (( marker_ok == 1 || force == 0 )) || return 1
}
if [[ -n "$explicit" ]]; then
  [[ "$explicit" == /dev/* && -n "${explicit#/dev/}" ]] || { printf 'ASHIPAOS_INSTALL_REFUSED_UNSAFE\n' >&2; exit 1; }
  path=$(canonical "$devroot/${explicit#/dev/}"); [[ -n "$path" && "${path##*/}" != */* ]] || { printf 'ASHIPAOS_INSTALL_REFUSED_UNSAFE\n' >&2; exit 1; }
  is_safe "$path" || { (( marker_invalid == 1 )) && printf 'ASHIPAOS_INSTALL_REFUSED_MARKER\n' >&2 || printf 'ASHIPAOS_INSTALL_REFUSED_UNSAFE\n' >&2; exit 1; }; printf '%s\n' "$path"; exit 0
fi
candidates=(); for entry in "$sysfs"/block/*; do [[ -e "$entry" ]] || continue; name=${entry##*/}; path="$devroot/$name"; is_safe "$path" && candidates+=("$path"); done
if (( ${#candidates[@]} != 1 )); then
  if (( marker_invalid == 1 )); then printf 'ASHIPAOS_INSTALL_REFUSED_MARKER\n' >&2; else printf 'ASHIPAOS_INSTALL_REFUSED_UNSAFE\n' >&2; fi
  printf 'expected exactly one safe install disk, found %d\n' "${#candidates[@]}" >&2
  exit 1
fi
printf '%s\n' "${candidates[0]}"
