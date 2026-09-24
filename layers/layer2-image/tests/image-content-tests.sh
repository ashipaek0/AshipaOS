#!/usr/bin/env bash
# Layer 2 image-content gate.
#   image-content-tests.sh           -> static contract only
#   image-content-tests.sh <image>   -> inspects the built image read-only:
#                                       MBR layout, zero gap, FAT16 boot files,
#                                       kernel.img header, and ext4 contents.
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
listing="$(mdir -b -i "$fat" ::)"
for f in aml_autoscript cfgload kernel.img dtb.img manifest.json; do
    grep -Fxq "::/$f" <<<"$listing" || fail "boot partition is missing $f (lower-case name required)"
    mcopy -n -i "$fat" "::$f" "$TMP/$f"
done

python3 - "$TMP" <<'PY' || fail "boot file check failed"
import hashlib, json, struct, sys
from pathlib import Path
d = Path(sys.argv[1])
for script in ("aml_autoscript", "cfgload"):
    if struct.unpack(">I", (d / script).read_bytes()[:4])[0] != 0x27051956:
        raise SystemExit(f"{script} is not a U-Boot script image")
if (d / "dtb.img").read_bytes()[:4] != b"\xd0\x0d\xfe\xed":
    raise SystemExit("dtb.img is not a flattened device tree")
kernel_img = (d / "kernel.img").read_bytes()
if kernel_img[:8] != b"ANDROID!":
    raise SystemExit("kernel.img has no Android header")
ksize, kaddr, rsize, raddr, _ssize, _saddr, _tags, page = struct.unpack_from("<8I", kernel_img, 8)
if page != 2048 or kaddr % 0x80000 or not ksize or not rsize:
    raise SystemExit("kernel.img header is inconsistent")
if kernel_img[page + 56:page + 60] != b"ARM\x64":
    raise SystemExit("kernel.img payload is not an uncompressed arm64 Image")
cmdline = kernel_img[64:576].rstrip(b"\0").decode()
if "root=LABEL=RootFS" not in cmdline or "console=ttyAML0" not in cmdline:
    raise SystemExit(f"unexpected kernel command line: {cmdline}")
manifest = json.loads((d / "manifest.json").read_text())
for name, digest in manifest["files"].items():
    if hashlib.sha256((d / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"manifest hash mismatch for {name}")
for script in ("aml_autoscript", "cfgload"):
    text = (d / script).read_bytes()[64:].decode(errors="replace")
    if "saveenv" in text or "mmc write" in text or "store " in text:
        raise SystemExit(f"{script} must never write eMMC or the saved environment")
PY

root_fs="$TMP/root.ext4"
dd if="$IMAGE" of="$root_fs" bs=1M skip=$((532480 * 512 / 1048576)) count=3584 conv=sparse status=none
label="$(debugfs -R 'stats' "$root_fs" 2>/dev/null | awk -F': *' '/^Filesystem volume name/ {print $2}')"
[[ "$label" == RootFS ]] || fail "root filesystem label is '$label', expected RootFS"
debugfs -R 'cat /etc/fstab' "$root_fs" 2>/dev/null | grep -Eq '^LABEL=RootFS[[:space:]]+/[[:space:]]+ext4' ||
    fail "root /etc/fstab does not mount LABEL=RootFS"
for f in /usr/libexec/ashipaos-jellyfin-mpv-shim \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0/manifest.json \
         /usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0/bin/jellyfin-mpv-shim \
         /usr/libexec/ashipaos-boot-status-handler \
         /etc/systemd/system/ashipaos-boot-status.service; do
    debugfs -R "stat $f" "$root_fs" 2>/dev/null | grep -q 'Type: regular' || fail "root filesystem is missing $f"
done
[[ -z "$(debugfs -R 'cat /etc/machine-id' "$root_fs" 2>/dev/null)" ]] || fail "image carries a fixed machine-id"

printf '%s\n' 'A95X Layer 2 image-content contract: PASS'
