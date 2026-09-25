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
assert {"initramfs-tools", "python3", "libmpv2", "libgl1-mesa-dri", "libegl-mesa0", "libgbm1",
        "fonts-dejavu-core", "busybox", "systemd-resolved", "systemd-timesyncd"} <= set(packages)
import re
debian = config["debian"]
assert re.fullmatch(r"\d{8}T\d{6}Z", debian["snapshot"]), "Debian must be pinned to a snapshot timestamp"
for key in ("mirror", "security_mirror"):
    assert debian[key].startswith("http://snapshot.debian.org/archive/") and debian[key].endswith("/{snapshot}")
assert debian["keyring"] == "/usr/share/keyrings/debian-archive-keyring.gpg"
assert "python3-mpv" not in packages
assert config["debian"]["suite"] == "trixie", "libmpv must be >= 0.38 (Jellyfin MPV Shim 3.0)"
assert {"firmware-realtek", "wireless-regdb", "iwd", "cage", "seatd", "ir-keytable"} <= set(packages)
# STORAGE partition growth (contracts/storage.md) needs sfdisk/partx and resize2fs.
assert {"util-linux", "e2fsprogs"} <= set(packages)
assert len(packages) == len(set(packages))
PY
[[ -f "$ROOT/rootfs-overlay/etc/systemd/network/20-wired.network" ]] || fail "network overlay is missing"
grep -q '^    install_boot_report$' "$SCRIPT" || fail "the no-UART boot report must always be installed"
grep -q 'systemctl enable iwd.service ashipaos-wifi-import.service' "$SCRIPT" || fail "Wi-Fi (iwd + wifi.txt import) must be enabled"
! grep -q 'Passphrase=' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-wifi-import" || fail "Wi-Fi import must store only the hashed PSK"
[[ -x "$ROOT/rootfs-overlay/usr/libexec/ashipaos-boot-report" ]] || fail "boot report script is missing"
! grep -Eq 'mmcblk|/dev/mmc|dd ' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-boot-report" || fail "boot report must not touch block devices directly"
# STORAGE partition growth (contracts/storage.md): grown once on first boot,
# before it is ever mounted, strictly ahead of Layer 2's storage.mount.
grep -q 'ashipaos-storage-grow' "$SCRIPT" || fail "the storage-grow helper must be installed into the rootfs"
grep -q 'ashipaos-storage-grow.service' "$SCRIPT" || fail "the storage-grow service unit must be installed into the rootfs"
grep -q 'ashipaos-storage.conf' "$SCRIPT" || fail "the /storage tmpfiles.d rule must be installed into the rootfs"
[[ -x "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" ]] || fail "storage-grow script is missing or not executable"
grep -q 'mmcblk1' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" || fail "storage-grow must explicitly refuse the box's eMMC (mmcblk1)"
grep -q 'removable' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" || fail "storage-grow must require the target disk be reported removable"
grep -q -- '--no-tell-kernel' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" || fail "storage-grow must not force a whole-disk kernel partition-table reread"
[[ -f "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-storage-grow.service" ]] || fail "storage-grow service unit is missing"
[[ -f "$ROOT/rootfs-overlay/usr/lib/tmpfiles.d/ashipaos-storage.conf" ]] || fail "the /storage tmpfiles.d rule is missing"
grep -q ': >"$ROOTFS/etc/machine-id"' "$SCRIPT" || fail "rootfs must not ship a fixed machine-id"
grep -q -- '--keyring="$DEBIAN_KEYRING" --force-check-gpg' "$SCRIPT" || fail "debootstrap must verify Release signatures"
! grep -Eq 'DEBIAN_(MIRROR|SUITE)=.*\$\{DEBIAN_' "$SCRIPT" || fail "Debian sources must not be overridable from the environment"
printf '%s\n' 'A95X Layer 1 contract: PASS'
