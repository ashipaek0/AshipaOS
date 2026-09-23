#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/dev" "$tmp/iso" "$tmp/media"
cat > "$tmp/bin/mount" <<'SH'
#!/usr/bin/env bash
candidate=$(readlink -f "$3"); destination=$4
[[ -d "$TEST_MEDIA/${candidate##*/}" ]] || exit 1
mkdir -p "$destination/install"
cp -a "$TEST_MEDIA/${candidate##*/}/." "$destination/install/"
SH
cat > "$tmp/bin/umount" <<'SH'
#!/usr/bin/env bash
rm -rf "$1/install"
SH
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" SOURCE_TEST_MODE=1 SOURCE_DEV_ROOT="$tmp/dev" SOURCE_MOUNT="$tmp/iso" TEST_MEDIA="$tmp/media"
case "$mode" in
 explicit|wrong-explicit|payload-only|manifest-only|empty) device=sda1;;
 optical) device=sr0;;
 partitioned-usb) device=sdb1;;
 whole-usb) device=sdc;;
 nonremovable-usb) device=sdd;;
 ancestry) device=sde1;;
 *) exit 2;;
esac
: > "$tmp/dev/$device"; mkdir -p "$tmp/media/$device"
case "$mode" in
 payload-only) printf data > "$tmp/media/$device/appliance.img.zst";;
 manifest-only) printf data > "$tmp/media/$device/appliance.img.manifest";;
 empty) : > "$tmp/media/$device/appliance.img.zst"; : > "$tmp/media/$device/appliance.img.manifest";;
 *) printf data > "$tmp/media/$device/appliance.img.zst"; printf manifest > "$tmp/media/$device/appliance.img.manifest";;
esac
if [[ "$mode" == ancestry ]]; then ln -s "$device" "$tmp/dev/alias"; fi
if [[ "$mode" == wrong-explicit ]]; then
  export INSTALL_SOURCE=/dev/sda2
elif [[ "$mode" == explicit ]]; then export INSTALL_SOURCE=/dev/sda1
elif [[ "$mode" == ancestry ]]; then export INSTALL_SOURCE=/dev/alias
else unset INSTALL_SOURCE || true; fi
if [[ "$mode" == payload-only || "$mode" == manifest-only || "$mode" == empty || "$mode" == wrong-explicit ]]; then
  ! "$root/installer/discover-source.sh"
else
  [[ $("$root/installer/discover-source.sh") == "$(readlink -f "$tmp/dev/$device")" ]]
  [[ -s "$tmp/iso/install/appliance.img.zst" && -s "$tmp/iso/install/appliance.img.manifest" ]]
fi
