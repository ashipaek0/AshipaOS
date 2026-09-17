#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${1:-$ROOT/build/output/ashipaos-x86_64.img}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
# Ubuntu 24.04's ovmf package provides /usr/share/ovmf/OVMF.fd as the combined
# image accepted by QEMU's -bios loader. OVMF_CODE_4M.fd is only the code flash
# region and is not a complete PC BIOS image, so resolve the combined image
# from the installed package manifest instead of guessing firmware paths.
OVMF="$(dpkg-query -L ovmf 2>/dev/null | awk '$0 == "/usr/share/ovmf/OVMF.fd" { print; exit }')"
[[ -n "$OVMF" && -r "$OVMF" ]] || {
  echo "Readable combined OVMF firmware was not found in the installed ovmf package" >&2
  exit 1
}

set +e
timeout 120 qemu-system-x86_64 \
  -machine q35,accel=tcg -m 1024 -smp 2 -nographic -no-reboot \
  -bios "$OVMF" \
  -drive "file=$IMAGE,format=raw,if=virtio" >"$LOG" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -eq 0 || "$STATUS" -eq 124 ]] || { cat "$LOG"; exit "$STATUS"; }
grep -Eq 'Welcome to Debian GNU/Linux 12|Reached target .*Graphical Interface' "$LOG" || {
  cat "$LOG"
  echo "VM did not reach the operating system" >&2
  exit 1
}
echo "test-boot: PASS"
