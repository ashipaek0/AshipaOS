#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-}"
ROOTFS="${2:-$ROOT/build/rootfs/${TARGET:-missing}}"
OUTPUT="${3:-$ROOT/build/output}"
LOOP_DEVICE=""
ROOT_MOUNT=""
STORAGE_MOUNT=""

cleanup() {
  set +e
  sync
  [[ -z "$STORAGE_MOUNT" ]] || umount "$STORAGE_MOUNT" 2>/dev/null || true
  [[ -z "$ROOT_MOUNT" ]] || umount -R "$ROOT_MOUNT" 2>/dev/null || true
  [[ -z "$LOOP_DEVICE" ]] || losetup --detach "$LOOP_DEVICE" 2>/dev/null || true
  [[ -z "$STORAGE_MOUNT" ]] || rm -rf "$STORAGE_MOUNT"
  [[ -z "$ROOT_MOUNT" ]] || rm -rf "$ROOT_MOUNT"
}
trap cleanup EXIT INT TERM

[[ "$TARGET" == x86_64 ]] || { echo "Only x86_64 image assembly is implemented" >&2; exit 2; }
[[ "$(id -u)" -eq 0 && -x "$ROOTFS/bin/bash" ]] || {
  echo "Run as root with a configured rootfs" >&2
  exit 1
}

for command in parted losetup mkfs.vfat mkfs.ext4 rsync grub-install zstd; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done

CONFIG="$ROOT/build/targets/$TARGET.yaml"
read_image_value() {
  local key="$1"
  awk -v wanted="$key" '
    /^image:$/ { section=1; next }
    section && /^[^[:space:]#]/ { exit }
    section && $1 == wanted ":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$CONFIG"
}

SIZE_MIB="$(read_image_value size_mib)"
ESP_MIB="$(read_image_value esp_size_mib)"
STORAGE_MIB="$(read_image_value storage_size_mib)"
ROOT_LABEL="$(read_image_value root_label)"
STORAGE_LABEL="$(read_image_value storage_label)"
CMDLINE="$(awk '
  /^  cmdline:$/ { section=1; next }
  section && /^  [^[:space:]#]/ { exit }
  section && $1 == "value:" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
' "$CONFIG")"
[[ "$SIZE_MIB" =~ ^[0-9]+$ && "$ESP_MIB" =~ ^[0-9]+$ && "$STORAGE_MIB" =~ ^[0-9]+$ ]] || {
  echo "Invalid image sizes in $CONFIG" >&2
  exit 2
}
[[ "$CMDLINE" == *"root=LABEL=$ROOT_LABEL"* ]] || {
  echo "Kernel command line does not select the declared root label" >&2
  exit 2
}
ROOT_END_MIB=$((SIZE_MIB - STORAGE_MIB))
(( ROOT_END_MIB > ESP_MIB + 512 )) || { echo "Image root partition is too small" >&2; exit 2; }

KERNEL_VERSION="$(cat "$ROOTFS/etc/ashipaos-kernel-version")"
[[ -f "$ROOTFS/boot/vmlinuz-$KERNEL_VERSION" && -f "$ROOTFS/boot/initrd.img-$KERNEL_VERSION" ]] || {
  echo "Rootfs boot bundle is incomplete" >&2
  exit 1
}

mkdir -p "$OUTPUT"
IMAGE="$OUTPUT/ashipaos-$TARGET.img"
PACKAGES_LOCK="$OUTPUT/ashipaos-$TARGET.packages.lock"
rm -f "$IMAGE" "$IMAGE.zst" "$IMAGE.zst.sha256" "$PACKAGES_LOCK" \
  "$OUTPUT/ashipaos-$TARGET.manifest.json"
cp -- "$ROOTFS/etc/ashipaos-packages.lock" "$PACKAGES_LOCK"
PACKAGES_LOCK_SHA="$(sha256sum "$PACKAGES_LOCK" | cut -d' ' -f1)"
truncate --size="${SIZE_MIB}M" "$IMAGE"
parted --script "$IMAGE" \
  mklabel gpt \
  mkpart ESP fat32 1MiB "${ESP_MIB}MiB" \
  set 1 esp on \
  mkpart root ext4 "${ESP_MIB}MiB" "${ROOT_END_MIB}MiB" \
  mkpart storage ext4 "${ROOT_END_MIB}MiB" 100%

LOOP_DEVICE="$(losetup --find --show --partscan "$IMAGE")"
udevadm settle
mkfs.vfat -F 32 -n ASHIPA_EFI "${LOOP_DEVICE}p1"
mkfs.ext4 -F -L "$ROOT_LABEL" "${LOOP_DEVICE}p2"
mkfs.ext4 -F -L "$STORAGE_LABEL" "${LOOP_DEVICE}p3"

ROOT_MOUNT="$(mktemp -d)"
STORAGE_MOUNT="$(mktemp -d)"
mount "${LOOP_DEVICE}p2" "$ROOT_MOUNT"
rsync -aHAX --numeric-ids "$ROOTFS/" "$ROOT_MOUNT/"
mkdir -p "$ROOT_MOUNT/boot/efi"
mount "${LOOP_DEVICE}p1" "$ROOT_MOUNT/boot/efi"
mount "${LOOP_DEVICE}p3" "$STORAGE_MOUNT"

install -d -o 1000 -g 1000 -m 0700 "$STORAGE_MOUNT/config" "$STORAGE_MOUNT/state"
install -d -o 1000 -g 1000 -m 0755 "$STORAGE_MOUNT/cache" "$STORAGE_MOUNT/thumbnails"
install -d -o 1000 -g 1000 -m 0750 "$STORAGE_MOUNT/downloads" "$STORAGE_MOUNT/logs"
install -d -o 0 -g 0 -m 0755 "$STORAGE_MOUNT/app"

grub-install --target=x86_64-efi --efi-directory="$ROOT_MOUNT/boot/efi" \
  --boot-directory="$ROOT_MOUNT/boot" --removable --no-nvram
cat >"$ROOT_MOUNT/boot/grub/grub.cfg" <<EOF
set timeout=2
set default=0
menuentry 'AshipaOS' {
  search --no-floppy --label --set=root $ROOT_LABEL
  linux /boot/vmlinuz-$KERNEL_VERSION $CMDLINE
  initrd /boot/initrd.img-$KERNEL_VERSION
}
EOF

SOURCE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
INPUT_SHA="$(cat "$CONFIG" "$ROOT/build/config/packages.lock" | sha256sum | cut -d' ' -f1)"
BUILD_ID="${SOURCE_SHA:0:12}-${INPUT_SHA:0:12}"
VERSION="${ASHIPAOS_VERSION:-0.1.0-dev}"
install -d "$ROOT_MOUNT/etc/ashipaos"
printf '%s\n' "$VERSION" >"$ROOT_MOUNT/etc/ashipaos/version"
printf '%s\n' "$TARGET" >"$ROOT_MOUNT/etc/ashipaos/target"
printf '%s\n' "$BUILD_ID" >"$ROOT_MOUNT/etc/ashipaos/build-id"
sync
umount "$STORAGE_MOUNT"; rmdir "$STORAGE_MOUNT"; STORAGE_MOUNT=""
umount -R "$ROOT_MOUNT"; rmdir "$ROOT_MOUNT"; ROOT_MOUNT=""
losetup --detach "$LOOP_DEVICE"; LOOP_DEVICE=""

zstd --threads=0 --force --quiet "$IMAGE" -o "$IMAGE.zst"
(cd "$OUTPUT" && sha256sum "$(basename "$IMAGE.zst")" >"$(basename "$IMAGE.zst").sha256")
IMAGE_SHA="$(sha256sum "$IMAGE.zst" | cut -d' ' -f1)"
python3 - "$OUTPUT/ashipaos-$TARGET.manifest.json" "$VERSION" "$BUILD_ID" "$TARGET" \
  "$SOURCE_SHA" "$INPUT_SHA" "$KERNEL_VERSION" "$(basename "$IMAGE.zst")" "$IMAGE_SHA" \
  "$(basename "$PACKAGES_LOCK")" "$PACKAGES_LOCK_SHA" <<'PYEOF'
import json, sys
manifest = {
    "schema_version": 1,
    "version": sys.argv[2],
    "build_id": sys.argv[3],
    "target": sys.argv[4],
    "source_commit": sys.argv[5],
    "inputs_sha256": sys.argv[6],
    "kernel_version": sys.argv[7],
    "image": sys.argv[8],
    "sha256": sys.argv[9],
    "packages_lock": {"file": sys.argv[10], "sha256": sys.argv[11]},
    "verification": {"build": "pending-ci", "vm": "pending-ci", "hardware": "blocked"},
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2, sort_keys=True)
    output.write("\n")
PYEOF
echo "Created $IMAGE.zst"
