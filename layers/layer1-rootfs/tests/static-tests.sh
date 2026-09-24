#!/usr/bin/env bash
# Layer 1 STATIC: usage contract, configuration and overlay inputs.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
CONFIG="$ROOT/layers/layer1-rootfs/config/rootfs-config.yaml"
TARGET="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$SCRIPT"
# Argument errors are reported before any privilege escalation.
set +e
out="$(bash "$SCRIPT" 2>&1)"; status=$?
set -e
[[ $status -eq 2 ]] && grep -q '^Usage:' <<<"$out" || fail "no-argument invocation must print usage and exit 2"
bash "$SCRIPT" amd64 out.tar.gz >/dev/null 2>&1 && fail "non-arm64 architecture was accepted"
bash "$SCRIPT" arm64 out.tar.gz other-box >/dev/null 2>&1 && fail "foreign target was accepted"

python3 - "$CONFIG" "$TARGET" <<'PY' || fail "rootfs configuration is inconsistent"
import sys, yaml
config, target = (yaml.safe_load(open(p, encoding="utf-8")) for p in sys.argv[1:])
packages = [p for group in config["packages"].values() for p in group]
assert config["architecture"] == "arm64"
assert target["mainline_boot"]["kernel_package"] in packages
assert {"initramfs-tools", "python3", "libmpv2", "busybox", "systemd-resolved"} <= set(packages)
assert "python3-mpv" not in packages
assert len(packages) == len(set(packages))
PY
[[ -f "$ROOT/rootfs-overlay/etc/systemd/network/20-wired.network" ]] || fail "network overlay is missing"
grep -q ': >"$ROOTFS/etc/machine-id"' "$SCRIPT" || fail "rootfs must not ship a fixed machine-id"
printf '%s\n' 'A95X Layer 1 contract: PASS'
