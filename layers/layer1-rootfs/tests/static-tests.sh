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
# aplay/amixer for the boot report's audio diagnostics (dmix failed on the
# exact unit; see rootfs-overlay/etc/asound.conf).
assert "alsa-utils" in packages
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
# removable=0 is real on this hardware's own SD slot (see the script's
# docstring), so it is logged as a diagnostic, not enforced as a gate; the
# eMMC name check just above is the actual safety boundary.
grep -q 'removable' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" || fail "storage-grow must at least log the disk's removable flag"
grep -q -- '--no-tell-kernel' "$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow" || fail "storage-grow must not force a whole-disk kernel partition-table reread"
[[ -f "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-storage-grow.service" ]] || fail "storage-grow service unit is missing"
[[ -f "$ROOT/rootfs-overlay/usr/lib/tmpfiles.d/ashipaos-storage.conf" ]] || fail "the /storage tmpfiles.d rule is missing"
# Without DefaultDependencies=no + Before=local-fs.target, this ordinary
# service's implicit After=sysinit.target forms a real cycle with
# local-fs.target (a storage.mount member pulled in ahead of it by its own
# fstab line) -- systemd resolves it by dropping local-fs.target from the
# boot transaction, so STORAGE silently never mounts on any boot
# (evidence/amlogic/a95x-f3-air/boot-2026-09-25c/; proven for real, not just
# grepped, by tests/e2e/test-systemd-ordering.sh).
STORAGE_GROW_SERVICE="$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-storage-grow.service"
grep -qx 'DefaultDependencies=no' "$STORAGE_GROW_SERVICE" || fail "storage-grow.service must set DefaultDependencies=no (see the ordering-cycle comment in the unit)"
grep -qx 'Before=local-fs.target' "$STORAGE_GROW_SERVICE" || fail "storage-grow.service must run before local-fs.target"
# Audio: dmix failed to open its slave on the exact unit (silent playback
# every time); /etc/asound.conf routes mpv straight to hw:0,0 instead.
grep -q 'etc/asound.conf' "$SCRIPT" || fail "asound.conf must be installed into the rootfs"
[[ -f "$ROOT/rootfs-overlay/etc/asound.conf" ]] || fail "asound.conf is missing"
grep -q 'type plug' "$ROOT/rootfs-overlay/etc/asound.conf" || fail "asound.conf must route through plug, not dmix"

# IR diagnostics: read-only, no writes, no network -- see the service file.
grep -q 'ashipaos-ir-log.service' "$SCRIPT" || fail "the IR diagnostics service must be installed and enabled"
[[ -f "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-ir-log.service" ]] || fail "ashipaos-ir-log.service is missing"
! grep -Eq 'mmcblk|/dev/mmc|curl |wget ' "$ROOT/rootfs-overlay/etc/systemd/system/ashipaos-ir-log.service" ||
    fail "ashipaos-ir-log.service must stay read-only and offline"

grep -q ': >"$ROOTFS/etc/machine-id"' "$SCRIPT" || fail "rootfs must not ship a fixed machine-id"
grep -q -- '--keyring="$DEBIAN_KEYRING" --force-check-gpg' "$SCRIPT" || fail "debootstrap must verify Release signatures"
! grep -Eq 'DEBIAN_(MIRROR|SUITE)=.*\$\{DEBIAN_' "$SCRIPT" || fail "Debian sources must not be overridable from the environment"
printf '%s\n' 'A95X Layer 1 contract: PASS'
