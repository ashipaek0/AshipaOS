#!/usr/bin/env bash
# E2E: ashipaos-boot-success really parses and rewrites active-root.txt (the
# contracts/os-ota.md pending-confirmation step), not merely contains the
# right strings. Runs the real script against a fake systemctl and a real
# FAT/vfat-shaped boot mount stand-in (a plain directory: the script only
# needs a writable path, not an actual filesystem type).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/rootfs-overlay/usr/libexec/ashipaos-boot-success"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/boot"

fake_systemctl() {
    cat >"$TMP/bin/systemctl" <<EOF
#!/bin/sh
[ "\$1" = is-active ] && [ "\$2" = --quiet ] || exit 1
[ "\$HEALTHY" = 1 ]
EOF
    chmod 0755 "$TMP/bin/systemctl"
}
fake_systemctl
export PATH="$TMP/bin:$PATH"

run() {
    ASHIPAOS_BOOT_MOUNT="$TMP/boot" ASHIPAOS_CONSOLE="$TMP/console" HEALTHY="$1" bash "$SCRIPT"
}

# Healthy, pending boot: pending must clear, active_root must be preserved,
# boot_tries must reset.
printf 'active_root=b\npending=1\nboot_tries=2\n' >"$TMP/boot/active-root.txt"
run 1 >/dev/null 2>&1 || fail "a healthy pending boot must be confirmed"
cmp -s "$TMP/boot/active-root.txt" <(printf 'active_root=b\npending=0\nboot_tries=0\n') ||
    { cat "$TMP/boot/active-root.txt" >&2; fail "pending was not cleared correctly"; }
grep -q 'ASHIPAOS_BOOT_SUCCESS=1' "$TMP/console" || fail "console marker was not written"

# Healthy, already-confirmed boot: file must be left untouched (no rewrite of
# a file that does not need it, and no risk of it on a read-only fallback).
printf 'active_root=a\npending=0\nboot_tries=0\n' >"$TMP/boot/active-root.txt"
before="$(stat -c '%Y' "$TMP/boot/active-root.txt")"
sleep 1
run 1 >/dev/null 2>&1 || fail "a healthy non-pending boot must still be confirmed"
after="$(stat -c '%Y' "$TMP/boot/active-root.txt")"
[[ "$before" == "$after" ]] || fail "active-root.txt was rewritten when pending was already 0"

# Unhealthy: must fail closed and never clear pending.
printf 'active_root=a\npending=1\nboot_tries=1\n' >"$TMP/boot/active-root.txt"
if run 0 >/dev/null 2>&1; then fail "an unhealthy boot must not be confirmed"; fi
grep -q '^pending=1$' "$TMP/boot/active-root.txt" || fail "pending was cleared despite an unhealthy boot"

# Corrupt active_root: must fail closed and never write back a guess.
printf 'active_root=x\npending=1\nboot_tries=1\n' >"$TMP/boot/active-root.txt"
if run 1 >/dev/null 2>&1; then fail "an invalid active_root must not be accepted"; fi
grep -q '^active_root=x$' "$TMP/boot/active-root.txt" || fail "a corrupt active-root.txt was rewritten instead of rejected"

printf '%s\n' 'PASS: ashipaos-boot-success E2E'
