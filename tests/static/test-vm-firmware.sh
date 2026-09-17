#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOT_TEST="$ROOT/tests/vm/test-boot.sh"

grep -Fq 'dpkg-query -L ovmf' "$BOOT_TEST"
grep -Fq '$0 == "/usr/share/ovmf/OVMF.fd"' "$BOOT_TEST"
grep -Fq '[[ -n "$OVMF" && -r "$OVMF" ]]' "$BOOT_TEST"

if grep -Eq 'OVMF_CODE(_4M)?\.fd' <(sed '/^#/d' "$BOOT_TEST"); then
  echo "VM boot test must not pass a split OVMF code image to QEMU -bios" >&2
  exit 1
fi

grep -Fq -- '-bios "$OVMF"' "$BOOT_TEST"
echo "test-vm-firmware: PASS"
