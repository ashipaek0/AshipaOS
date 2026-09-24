#!/usr/bin/env bash
# STATIC: the boot-status endpoint and readiness marker are installed by
# Layer 1 for this target and only depend on units that exist.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY="$ROOT/rootfs-overlay"
HANDLER="$OVERLAY/usr/libexec/ashipaos-boot-status-handler"
SERVICE="$OVERLAY/etc/systemd/system/ashipaos-boot-status.service"
SUCCESS="$OVERLAY/etc/systemd/system/ashipaos-boot-success.service"
ROOTFS_CONFIG="$ROOT/layers/layer1-rootfs/config/rootfs-config.yaml"
ROOTFS_SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
TARGET="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$HANDLER" && -f "$SERVICE" && -f "$SUCCESS" ]] || fail "boot-status overlay files exist"
python3 - "$ROOTFS_CONFIG" "$TARGET" <<'PY' || fail "busybox is installed and the target enables boot status"
import sys, yaml
config, target = (yaml.safe_load(open(p, encoding="utf-8")) for p in sys.argv[1:])
assert "busybox" in [p for group in config["packages"].values() for p in group]
assert target["features"]["boot_status"] is True
PY
grep -q 'install_boot_status' "$ROOTFS_SCRIPT" || fail "rootfs builder installs boot-status assets"

# Handler is fixed-response-only and bounds the request line.
grep -q 'head -c 4096' "$HANDLER" || fail "handler bounds request input"
grep -q 'ASHIPAOS_BOOT_STATUS=OK' "$HANDLER" || fail "handler has fixed success body"
! grep -Eq '(^|[[:space:]])(curl|wget|nc)([[:space:]]|$)' "$HANDLER" || fail "handler does not invoke network clients"
grep -q 'HTTP/1.1 404 Not Found' "$HANDLER" || fail "handler rejects unsupported paths"
grep -q 'HTTP/1.1 405 Method Not Allowed' "$HANDLER" || fail "handler rejects unsupported methods"

grep -qx 'DynamicUser=yes' "$SERVICE" || fail "service is non-root"
grep -qx 'ExecStart=/bin/busybox nc -ll -p 8080 -e /usr/libexec/ashipaos-boot-status-handler' "$SERVICE" || fail "service uses the validated busybox nc command"
! grep -qEi 'ssh|password|credential' "$SERVICE" "$SUCCESS" "$HANDLER" || fail "boot-status assets contain no SSH or credentials"

# Every ashipaos-* unit a boot-status unit depends on must ship in the overlay.
for unit in "$SERVICE" "$SUCCESS"; do
  grep -Eqx 'WantedBy=multi-user.target' "$unit" || fail "$(basename "$unit") is enabled for multi-user.target"
  while read -r dep; do
    [[ -f "$OVERLAY/etc/systemd/system/$dep" ]] || fail "$(basename "$unit") depends on missing unit $dep"
  done < <(grep -E '^(Requires|Wants|After|BindsTo)=' "$unit" | cut -d= -f2 | tr ' ' '\n' | grep '^ashipaos-' || true)
done
printf '%s\n' 'PASS: boot-status static contract'
