#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sys/block" "$tmp/dev"
make_disk() {
  local name=$1 size=$2 removable=${3:-0} ro=${4:-0} type=${5:-}
  mkdir -p "$tmp/sys/block/$name"
  { printf '%s\n' "$size"; printf '%s\n' "$removable"; printf '%s\n' "$ro"; printf '%s\n' "$type"; } > "$tmp/sys/block/$name/attrs"
  : > "$tmp/dev/$name"
}
run() { SYSFS_ROOT="$tmp/sys" DEV_ROOT="$tmp/dev" "$ROOT/installer/select-target.sh" --fixture-root "$@"; }
case "$mode" in
  partition_helper) [[ "$(DEV_ROOT=/dev bash -c 'source "$1"; partition_path /dev/sda 3' _ "$ROOT/installer/partition-path.sh")" == /dev/sda3 ]]; [[ "$(DEV_ROOT=/dev bash -c 'source "$1"; partition_path /dev/nvme0n1 3' _ "$ROOT/installer/partition-path.sh")" == /dev/nvme0n1p3 ]]; [[ "$(DEV_ROOT=/dev bash -c 'source "$1"; partition_path /dev/loop0 2' _ "$ROOT/installer/partition-path.sh")" == /dev/loop0p2 ]]; [[ "$(DEV_ROOT=/dev bash -c 'source "$1"; partition_path /dev/vda 3' _ "$ROOT/installer/partition-path.sh")" == /dev/vda3 ]];;
  zero) ! run ;;
  multiple) make_disk sda 22000000000; make_disk sdb 22000000000; ! run ;;
  safe) make_disk sda 22000000000; [[ $(run) == "$tmp/dev/sda" ]];;
  unsafe) make_disk sr0 22000000000; ! run ;;
  removable) make_disk sda 22000000000 1; ! run ;;
  readonly) make_disk sda 22000000000 0 1; ! run ;;
  undersized) make_disk sda 1000000000; ! run ;;
  occupied) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1"; : > "$tmp/dev/sda1"; ! run ;;
  source) make_disk sda 22000000000; ! INSTALL_SOURCE=/dev/sda1 run ;;
  source_symlink) make_disk sda 22000000000; : > "$tmp/dev/sda1"; ln -s sda1 "$tmp/dev/by-id-installer"; ! INSTALL_SOURCE="$tmp/dev/by-id-installer" run ;;
  nvme) make_disk nvme0n1 22000000000; [[ $(run ashipaos.install_target=/dev/nvme0n1) == "$tmp/dev/nvme0n1" ]];;
  explicit) make_disk sda 22000000000; ! run ashipaos.install_target=/dev/sdb; [[ $(run ashipaos.install_target=/dev/sda) == "$tmp/dev/sda" ]];;
  holder) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/holders"; : > "$tmp/sys/block/sda/holders/dm-0"; ! run ;;
  child_signature) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1"; : > "$tmp/dev/sda1"; ! run ashipaos.force=1 ;;
  force_marker) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1" "$tmp/sys/block/sda/sda2" "$tmp/sys/block/sda/sda3" "$tmp/marker/var/lib/ashipaos"; printf 'installed\n' > "$tmp/marker/var/lib/ashipaos/install-complete"; : > "$tmp/dev/sda1"; : > "$tmp/dev/sda2"; : > "$tmp/dev/sda3"; export FIXTURE_MARKER_ROOT="$tmp/marker"; run ashipaos.force=1 | grep -Fx "$tmp/dev/sda" ;;
  force_extra_partition) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1" "$tmp/sys/block/sda/sda2" "$tmp/sys/block/sda/sda3" "$tmp/sys/block/sda/sda4" "$tmp/marker/var/lib/ashipaos"; printf 'installed\n' > "$tmp/marker/var/lib/ashipaos/install-complete"; : > "$tmp/dev/sda1"; : > "$tmp/dev/sda2"; : > "$tmp/dev/sda3"; : > "$tmp/dev/sda4"; export FIXTURE_MARKER_ROOT="$tmp/marker"; ! run ashipaos.force=1 ;;
  force_env_only) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1"; : > "$tmp/dev/sda1"; export ASHIPAOS_FORCE_VALID_MARKER=1; ! run ashipaos.force=1 ;;
  no_fixture_flag) make_disk sda 22000000000; ! SYSFS_ROOT="$tmp/sys" DEV_ROOT="$tmp/dev" "$ROOT/installer/select-target.sh" ;;
  wrong_marker) make_disk sda 22000000000; mkdir -p "$tmp/sys/block/sda/sda1" "$tmp/marker/var/lib/ashipaos"; printf 'not-installed\n' > "$tmp/marker/var/lib/ashipaos/install-complete"; : > "$tmp/dev/sda1"; export FIXTURE_MARKER_ROOT="$tmp/marker"; ! run ashipaos.force=1 ;;
  *) exit 2;;
esac
