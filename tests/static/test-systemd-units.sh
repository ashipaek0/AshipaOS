#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for unit in "$ROOT"/rootfs-overlay/etc/systemd/system/*.service; do
  grep -q '^\[Unit\]' "$unit"
  grep -q '^\[Service\]' "$unit"
done
grep -q '^User=ashipaos$' "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-display.service"
grep -q '^NoNewPrivileges=yes$' "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-display.service"
grep -q '^ConditionFileIsExecutable=/storage/app/current/bin/ashipaos$' \
  "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-display.service"
echo "test-systemd-units: PASS"
