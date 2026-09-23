#!/usr/bin/env bash
# Return the numbered partition for a canonical whole-disk device.
partition_path() {
  local device=${1:?device} number=${2:?partition number} disk root
  disk=${device##*/}
  root=${DEV_ROOT:-/dev}
  case "$disk" in
    nvme*n*|mmcblk*) printf '%s/%sp%s\n' "$root" "$disk" "$number";;
    *) printf '%s/%s%s\n' "$root" "$disk" "$number";;
  esac
}
