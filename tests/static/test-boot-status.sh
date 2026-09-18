#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HANDLER="$ROOT/rootfs-overlay/usr/libexec/ashipaos-boot-status-handler"
SERVICE="$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-boot-status.service"
ROOTFS_CONFIG="$ROOT/layers/layer1-rootfs/config/rootfs-config.yaml"
ROOTFS_SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
FULL_BUILD="$ROOT/build/scripts/full-build.sh"
TARGET="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

[[ -x "$HANDLER" ]] || fail "handler is executable"
[[ -f "$SERVICE" ]] || fail "service exists"
grep -q '^    - busybox$' "$ROOTFS_CONFIG" || fail "rootfs declares busybox"
grep -q 'install_boot_status' "$ROOTFS_SCRIPT" || fail "rootfs builder installs boot-status assets"
grep -q 'build_layer1.*target' "$FULL_BUILD" || fail "full build passes target into rootfs builder"
grep -q '^features:' "$TARGET" || fail "target declares feature flags"
grep -q '^  boot_status: true$' "$TARGET" || fail "a95x target enables boot status"

# Handler is fixed-response-only and bounds the request line.
grep -q 'head -c 4096' "$HANDLER" || fail "handler bounds request input"
grep -q 'ASHIPAOS_BOOT_STATUS=OK' "$HANDLER" || fail "handler has fixed success body"
! grep -Eq '(^|[[:space:]])(curl|wget|nc)([[:space:]]|$)' "$HANDLER" || fail "handler does not invoke network clients"
grep -q 'HTTP/1.1 200 OK' "$HANDLER" || fail "handler emits success response"
grep -q 'HTTP/1.1 404 Not Found' "$HANDLER" || fail "handler rejects unsupported paths"
grep -q 'HTTP/1.1 405 Method Not Allowed' "$HANDLER" || fail "handler rejects unsupported methods"

# Service must be ordered, bounded to the target feature, and non-root.
grep -q '^After=network-online.target$' "$SERVICE" || fail "service starts after network-online"
grep -q '^Wants=network-online.target$' "$SERVICE" || fail "service wants network-online"
grep -q '^DynamicUser=yes$' "$SERVICE" || fail "service is non-root"
grep -q '^ExecStart=/bin/busybox nc -ll -p 8080 -e /usr/libexec/ashipaos-boot-status-handler$' "$SERVICE" || fail "service uses validated busybox nc command"
grep -q '^WantedBy=multi-user.target$' "$SERVICE" || fail "service has target install"
! grep -qEi 'ssh|password|credential' "$SERVICE" "$HANDLER" || fail "boot-status assets contain no SSH or credentials"

pass "boot-status static contract"
