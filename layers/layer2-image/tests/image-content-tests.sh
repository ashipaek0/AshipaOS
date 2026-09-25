#!/usr/bin/env bash
# Layer 2 image-content gate.
#   image-content-tests.sh           -> static contract only
#   image-content-tests.sh <image>   -> inspects the built image read-only:
#                                       MBR layout, zero gap, FAT16 boot files,
#                                       chain-load scripts, u-boot.ext, kernel,
#                                       and ext4 contents.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
IMAGE="${1:-}"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash "$SCRIPT" --validate >/dev/null 2>&1 || fail "image-config.yaml does not validate"
if [[ -z "$IMAGE" ]]; then
    printf '%s\n' 'A95X Layer 2 image-content contract: PASS (static only; no image given)'
    exit 0
fi

for cmd in sfdisk mdir mcopy debugfs python3; do
    command -v "$cmd" >/dev/null || fail "$cmd is required to inspect $IMAGE"
done
[[ -f "$IMAGE" && -s "$IMAGE" ]] || fail "image missing or empty: $IMAGE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MTOOLS_SKIP_CHECK=1

table="$(sfdisk -d "$IMAGE")"
grep -q '^label: dos$' <<<"$table" || fail "partition table is not DOS/MBR"
grep -Eq 'start= *8192, size= *524288, type=e, bootable' <<<"$table" || fail "partition 1 must be FAT16 LBA (0x0e), 256 MiB at 8192, bootable"
grep -Eq 'start= *532480, size= *7340032, type=83' <<<"$table" || fail "partition 2 must be Linux, 3584 MiB at 532480"

python3 - "$IMAGE" <<'PY' || fail "raw layout check failed"
import sys
with open(sys.argv[1], "rb") as image:
    mbr = image.read(512)
    gap = image.read(8191 * 512)
    boot = image.read(512)
if mbr[510:512] != b"\x55\xaa":
    raise SystemExit("missing MBR boot signature")
if any(gap):
    raise SystemExit("sectors 1..8191 must be zero (no raw SD payload writes)")
if boot[54:62] != b"FAT16   " or boot[43:54] != b"A95XBOOT   ":
    raise SystemExit(f"boot partition is not FAT16 labelled A95XBOOT: {boot[54:62]!r} {boot[43:54]!r}")
PY

fat="$IMAGE@@$((8192 * 512))"
DTB_NAME=meson-sm1-a95xf3-air.dtb
listing="$(mdir -b -i "$fat" ::)"
for f in aml_autoscript cfgload s905_autoscript u-boot.ext boot.scr ashipaos.id Image initrd.img "$DTB_NAME" manifest.json wifi.txt; do
    grep -Fxq "::/$f" <<<"$listing" || fail "boot partition is missing $f (lower-case name required)"
    mcopy -n -i "$fat" "::$f" "$TMP/$f"
done
! grep -Fxq '::/kernel.img' <<<"$listing" || fail "boot partition must not carry an Android kernel.img"

python3 - "$TMP" "$DTB_NAME" <<'PY' || fail "boot file check failed"
import hashlib, json, re, struct, sys
from pathlib import Path
d, dtb_name = Path(sys.argv[1]), sys.argv[2]
for script in ("aml_autoscript", "cfgload", "s905_autoscript", "boot.scr"):
    data = (d / script).read_bytes()
    if struct.unpack(">I", data[:4])[0] != 0x27051956:
        raise SystemExit(f"{script} is not a U-Boot script image")
    text = data[64:].decode(errors="replace")
    if re.search(r"saveenv|env save|mmc write|store |ums |fastboot", text):
        raise SystemExit(f"{script} must never write eMMC or the saved environment")
    if re.search(r"fatwrite mmc (?!0:1 )(?!\$\{ashipa_part\} )", text):
        raise SystemExit(f"{script} writes somewhere other than the SD card's boot partition")
for script in ("aml_autoscript", "cfgload", "s905_autoscript"):
    text = (d / script).read_bytes()[64:].decode(errors="replace")
    if "fatload mmc 0:1 0x01000000 u-boot.ext; then go 0x01000000" not in text:
        raise SystemExit(f"{script} does not chain-load u-boot.ext")
uboot = (d / "u-boot.ext").read_bytes()
if b"ashipaos-a95x-f3-air" not in uboot or b"amlogic/meson-sm1-a95xf3-air.dtb" not in uboot:
    raise SystemExit("u-boot.ext is not the AshipaOS A95X mainline U-Boot")
if (d / "Image").read_bytes()[56:60] != b"ARM\x64":
    raise SystemExit("Image is not an uncompressed arm64 kernel")
if (d / dtb_name).read_bytes()[:4] != b"\xd0\x0d\xfe\xed":
    raise SystemExit(f"{dtb_name} is not a flattened device tree")
boot_cmd = (d / "boot.scr").read_bytes()[64:].decode(errors="replace")
for needle in ("root=LABEL=RootFS", "console=ttyAML0", "booti", dtb_name):
    if needle not in boot_cmd:
        raise SystemExit(f"boot.scr lacks {needle}")
manifest = json.loads((d / "manifest.json").read_text())
for name, digest in manifest["files"].items():
    if hashlib.sha256((d / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"manifest hash mismatch for {name}")
PY

root_fs="$TMP/root.ext4"
dd if="$IMAGE" of="$root_fs" bs=1M skip=$((532480 * 512 / 1048576)) count=3584 conv=sparse status=none
label="$(debugfs -R 'stats' "$root_fs" 2>/dev/null | awk -F': *' '/^Filesystem volume name/ {print $2}')"
[[ "$label" == RootFS ]] || fail "root filesystem label is '$label', expected RootFS"
fstab="$(debugfs -R 'cat /etc/fstab' "$root_fs" 2>/dev/null)"
grep -Eq '^LABEL=RootFS[[:space:]]+/[[:space:]]+ext4' <<<"$fstab" || fail "root /etc/fstab does not mount LABEL=RootFS"
grep -Eq '^LABEL=A95XBOOT[[:space:]]+/boot/firmware[[:space:]]+vfat' <<<"$fstab" || fail "/etc/fstab does not mount the boot partition for the boot report"
for f in /usr/libexec/ashipaos-jellyfin-mpv-shim \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0/manifest.json \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0/bin/jellyfin-mpv-shim \
         /usr/libexec/ashipaos-boot-status-handler \
         /etc/systemd/system/ashipaos-boot-status.service \
         /usr/libexec/ashipaos-boot-report \
         /etc/systemd/system/ashipaos-boot-report.service \
         /usr/libexec/ashipaos-wifi-import \
         /etc/systemd/system/ashipaos-wifi-import.service \
         /etc/iwd/main.conf \
         /etc/systemd/system/seatd.service.d/ashipaos.conf; do
    debugfs -R "stat $f" "$root_fs" 2>/dev/null | grep -q 'Type: regular' || fail "root filesystem is missing $f"
done
[[ -z "$(debugfs -R 'cat /etc/machine-id' "$root_fs" 2>/dev/null)" ]] || fail "image carries a fixed machine-id"
# The image boots into Jellyfin MPV Shim: unit present and enabled, tty1 getty masked.
for f in /etc/systemd/system/ashipaos-jellyfin-mpv-shim.service \
         /usr/share/ashipaos/jellyfin-mpv-shim/conf.json \
         /usr/share/ashipaos/jellyfin-mpv-shim/mpv.conf; do
    debugfs -R "stat $f" "$root_fs" 2>/dev/null | grep -q 'Type: regular' || fail "root filesystem is missing $f"
done
[[ "$(debugfs -R 'stat /etc/systemd/system/multi-user.target.wants/ashipaos-jellyfin-mpv-shim.service' "$root_fs" 2>/dev/null \
    | awk -F'"' '/Fast link dest/ {print $2}')" == ../ashipaos-jellyfin-mpv-shim.service ]] ||
    fail "ashipaos-jellyfin-mpv-shim.service is not enabled at boot"
[[ "$(debugfs -R 'stat /etc/systemd/system/getty@tty1.service' "$root_fs" 2>/dev/null \
    | awk -F'"' '/Fast link dest/ {print $2}')" == /dev/null ]] || fail "getty@tty1.service is not masked"
[[ "$(debugfs -R 'stat /etc/systemd/system/multi-user.target.wants/ashipaos-boot-report.service' "$root_fs" 2>/dev/null \
    | awk -F'"' '/Fast link dest/ {print $2}')" == */ashipaos-boot-report.service ]] ||
    fail "ashipaos-boot-report.service is not enabled at boot"

printf '%s\n' 'A95X Layer 2 image-content contract: PASS'
