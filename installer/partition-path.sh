#!/usr/bin/env bash
# Return the numbered partition for a canonical whole-disk device.
partition_path() {
  local device=${1:?device} number=${2:?partition number} disk root
  disk=${device##*/}
  root=${DEV_ROOT:-/dev}
  # The kernel inserts "p" when the disk name ends in a digit (nvme0n1,
  # mmcblk0, loop0, md0).
  case "$disk" in
    *[0-9]) printf '%s/%sp%s\n' "$root" "$disk" "$number";;
    *) printf '%s/%s%s\n' "$root" "$disk" "$number";;
  esac
}
