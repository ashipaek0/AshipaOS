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
grep -Eq 'start= *532480, size= *4194304, type=83' <<<"$table" || fail "partition 2 (root_a) must be Linux, 2048 MiB at 532480"
grep -Eq 'start= *4726784, size= *4194304, type=83' <<<"$table" || fail "partition 3 (root_b) must be Linux, 2048 MiB at 4726784"
grep -Eq 'start= *8921088, size= *1048576, type=83' <<<"$table" || fail "partition 4 (storage) must be Linux, 512 MiB at 8921088"
[[ "$(grep -c 'start=' <<<"$table")" -eq 4 ]] || fail "expected exactly 4 partitions (boot, root_a, root_b, storage)"

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
DTB_BASE="${DTB_NAME%.dtb}"
listing="$(mdir -b -i "$fat" ::)"
for f in aml_autoscript cfgload s905_autoscript u-boot.ext boot.scr ashipaos.id active-root.txt manifest.json wifi.txt \
         Image-a initrd.img-a "$DTB_BASE-a.dtb"; do
    grep -Fxq "::/$f" <<<"$listing" || fail "boot partition is missing $f (lower-case name required)"
    mcopy -n -i "$fat" "::$f" "$TMP/$f"
done
! grep -Fxq '::/kernel.img' <<<"$listing" || fail "boot partition must not carry an Android kernel.img"
# Slot B has no boot files staged until an OS update installs into it.
! grep -Fxq '::/Image-b' <<<"$listing" || fail "boot partition must not carry slot B boot files on a fresh flash"

python3 - "$TMP" "$DTB_NAME" <<'PY' || fail "boot file check failed"
import hashlib, json, re, struct, sys
from pathlib import Path
d, dtb_name = Path(sys.argv[1]), sys.argv[2]
dtb_base = dtb_name[:-len(".dtb")]
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
if (d / "Image-a").read_bytes()[56:60] != b"ARM\x64":
    raise SystemExit("Image-a is not an uncompressed arm64 kernel")
if (d / f"{dtb_base}-a.dtb").read_bytes()[:4] != b"\xd0\x0d\xfe\xed":
    raise SystemExit(f"{dtb_base}-a.dtb is not a flattened device tree")
active_root = (d / "active-root.txt").read_text()
if active_root != "active_root=a\npending=0\nboot_tries=0\n":
    raise SystemExit(f"active-root.txt must start a fresh flash on slot A, not pending: {active_root!r}")
boot_cmd = (d / "boot.scr").read_bytes()[64:].decode(errors="replace")
# root= is assembled dynamically from active-root.txt's slot, never static.
for needle in ("active-root.txt", "active_root", "pending", "boot_tries",
               "root=LABEL=${root_label}", "console=ttyAML0", "booti",
               f"{dtb_base}-${{active_root}}.dtb", "Image-${active_root}", "initrd.img-${active_root}"):
    if needle not in boot_cmd:
        raise SystemExit(f"boot.scr lacks {needle}")
if "root=LABEL=RootFS" in boot_cmd:
    raise SystemExit("boot.scr must not set root= to a fixed, slot-independent label")
manifest = json.loads((d / "manifest.json").read_text())
if manifest["format"] != "ashipaos-a95x-boot-v4":
    raise SystemExit(f"unexpected manifest format: {manifest['format']}")
if manifest["active_root"] != "a" or manifest["root_partitions"]["a"]["populated"] is not True \
        or manifest["root_partitions"]["b"]["populated"] is not False:
    raise SystemExit("manifest must record a fresh flash as active slot A, with slot B unpopulated")
if not isinstance(manifest["max_boot_tries"], int) or manifest["max_boot_tries"] < 1:
    raise SystemExit("manifest max_boot_tries is missing or invalid")
if "storage_partition" not in manifest:
    raise SystemExit("manifest is missing the storage_partition entry")
for name, digest in manifest["files"].items():
    if hashlib.sha256((d / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"manifest hash mismatch for {name}")
PY

root_fs="$TMP/root-a.ext4"
dd if="$IMAGE" of="$root_fs" bs=1M skip=$((532480 * 512 / 1048576)) count=2048 conv=sparse status=none
label="$(debugfs -R 'stats' "$root_fs" 2>/dev/null | awk -F': *' '/^Filesystem volume name/ {print $2}')"
[[ "$label" == RootFS-A ]] || fail "root slot A filesystem label is '$label', expected RootFS-A"
fstab="$(debugfs -R 'cat /etc/fstab' "$root_fs" 2>/dev/null)"
# root= is set on the kernel cmdline by boot.scr (dynamic per active slot); a
# static / entry here would silently override that for whichever slot booted.
! grep -Eq '^[^#[:space:]]+[[:space:]]+/[[:space:]]+ext4' <<<"$fstab" || fail "root /etc/fstab must not have a static / entry"
grep -Eq '^LABEL=A95XBOOT[[:space:]]+/boot/firmware[[:space:]]+vfat' <<<"$fstab" || fail "/etc/fstab does not mount the boot partition for the boot report"
grep -Eq '^LABEL=STORAGE[[:space:]]+/storage[[:space:]]+ext4' <<<"$fstab" || fail "/etc/fstab does not mount the STORAGE partition"
grep -q 'x-systemd.growfs' <<<"$fstab" || fail "STORAGE mount must grow the filesystem online after ashipaos-storage-grow"
grep -q 'x-systemd.requires=ashipaos-storage-grow.service' <<<"$fstab" || fail "STORAGE mount must be ordered after ashipaos-storage-grow.service"
for f in /usr/libexec/ashipaos-jellyfin-mpv-shim \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/manifest.json \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/bin/jellyfin-mpv-shim \
         /usr/lib/tmpfiles.d/ashipaos-jellyfin-mpv-shim.conf \
         /usr/libexec/ashipaos-boot-status-handler \
         /etc/systemd/system/ashipaos-boot-status.service \
         /etc/systemd/system/ashipaos-boot-success.service \
         /usr/libexec/ashipaos-boot-report \
         /etc/systemd/system/ashipaos-boot-report.service \
         /usr/libexec/ashipaos-wifi-import \
         /etc/systemd/system/ashipaos-wifi-import.service \
         /etc/iwd/main.conf \
         /etc/systemd/system/seatd.service.d/ashipaos.conf \
         /usr/libexec/ashipaos-storage-grow \
         /etc/systemd/system/ashipaos-storage-grow.service \
         /usr/lib/tmpfiles.d/ashipaos-storage.conf; do
    debugfs -R "stat $f" "$root_fs" 2>/dev/null | grep -q 'Type: regular' || fail "root filesystem is missing $f"
done
! debugfs -R 'stat /usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0' "$root_fs" 2>/dev/null | grep -q 'Type: directory' ||
    fail "the app bundle must not carry a version subdirectory (whole-slot updates replace it, not this bundle)"
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

# Slot B: formatted and labelled, but empty until an OS update installs into
# it (contracts/os-ota.md); it must never carry root_a's content.
root_b_fs="$TMP/root-b.ext4"
dd if="$IMAGE" of="$root_b_fs" bs=1M skip=$((4726784 * 512 / 1048576)) count=2048 conv=sparse status=none
label_b="$(debugfs -R 'stats' "$root_b_fs" 2>/dev/null | awk -F': *' '/^Filesystem volume name/ {print $2}')"
[[ "$label_b" == RootFS-B ]] || fail "root slot B filesystem label is '$label_b', expected RootFS-B"
! debugfs -R 'ls -l /' "$root_b_fs" 2>/dev/null | grep -q 'jellyfin-mpv-shim' || fail "slot B must be empty on a fresh flash"

# STORAGE: formatted and labelled, empty (grown and populated at first boot).
storage_fs="$TMP/storage.ext4"
dd if="$IMAGE" of="$storage_fs" bs=1M skip=$((8921088 * 512 / 1048576)) count=512 conv=sparse status=none
storage_label="$(debugfs -R 'stats' "$storage_fs" 2>/dev/null | awk -F': *' '/^Filesystem volume name/ {print $2}')"
[[ "$storage_label" == STORAGE ]] || fail "storage filesystem label is '$storage_label', expected STORAGE"

printf '%s\n' 'A95X Layer 2 image-content contract: PASS'
