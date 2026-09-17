#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGURE="$ROOT/build/scripts/configure-rootfs.sh"

if grep -q 'systemd-tmpfiles.*--prefix=/storage' "$CONFIGURE"; then
  echo "Rootfs configuration must not traverse the host workspace with systemd-tmpfiles" >&2
  exit 1
fi

grep -Fq 'install -d -o 0 -g 0 -m 0755 "$ROOTFS/storage"' "$CONFIGURE"
grep -Fq '"$ROOTFS/storage/config" "$ROOTFS/storage/state"' "$CONFIGURE"
grep -Fq '"$ROOTFS/storage/downloads" "$ROOTFS/storage/logs"' "$CONFIGURE"
grep -Fq 'install -d -o 0 -g 0 -m 0755 "$ROOTFS/storage/app"' "$CONFIGURE"
