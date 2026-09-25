#!/usr/bin/env bash
# E2E: ashipaos-storage-grow's real safety gate and growth logic. The safety
# gate refusals (sfdisk -J, no partx) run against a plain file, exactly like
# layer2's own image build; the actual growth path additionally needs a real
# loop device, since partx -u updates the KERNEL's view of a partition and
# has nothing to update against a plain file.
#
# This exists because the safety gate regressed silently on real hardware:
# the exact unit's SD slot reports /sys/block/<disk>/removable = 0 (see the
# script's own docstring and contracts/storage.md), which used to be a hard
# refusal and left the STORAGE partition never grown and never mounted on
# every real boot (evidence/amlogic/a95x-f3-air/boot-2026-09-25b/). Only the
# exact eMMC device name is now a hard refusal; removable=0 elsewhere must
# still proceed.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/rootfs-overlay/usr/libexec/ashipaos-storage-grow"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for cmd in sfdisk partx losetup python3; do
    command -v "$cmd" >/dev/null || { echo "SKIP: $cmd is required for the storage-grow E2E" >&2; exit 0; }
done
[[ $EUID -eq 0 ]] || { echo "SKIP: the storage-grow E2E needs root for losetup/partx" >&2; exit 0; }

TMP="$(mktemp -d)"
LOOP_DEVICES=()
cleanup() {
    local dev
    for dev in "${LOOP_DEVICES[@]:-}"; do
        [[ -n "$dev" ]] && losetup -d "$dev" 2>/dev/null || true
    done
    rm -rf "$TMP"
}
trap cleanup EXIT

make_disk() {
    local disk="$TMP/$1"
    # The file is the FULL 64 MiB "real SD card" size up front (matching the
    # fake /sys/block size below): the partition table only uses the front
    # of it, exactly like a small base image dd'd onto a larger real card,
    # leaving real room after STORAGE for the script to actually grow into.
    truncate -s 64M "$disk"
    sfdisk --quiet --wipe always "$disk" <<EOF
label: dos
unit: sectors
start=2048, size=8192, type=e
start=10240, size=32768, type=83
start=45056, size=16384, type=83
start=61440, size=4096, type=83
EOF
    printf '%s\n' "$disk"
}

fake_sysblock() {
    local disk="$1" removable="$2" size_sectors="$3" root="$TMP/sys-$RANDOM"
    mkdir -p "$root/$disk"
    printf '%s' "$removable" >"$root/$disk/removable"
    printf '%s' "$size_sectors" >"$root/$disk/size"
    printf '%s\n' "$root"
}

run_grow() {
    local disk_name="$1" device="$2" sysblock="$3" marker="$4"
    ASHIPAOS_STORAGE_GROW_DISK="$disk_name" ASHIPAOS_STORAGE_GROW_DEVICE="$device" \
        ASHIPAOS_STORAGE_GROW_SYSBLOCK_ROOT="$sysblock" ASHIPAOS_STORAGE_GROW_MARKER="$marker" \
        python3 "$SCRIPT"
}

# 1. The exact eMMC name is refused outright, even with a valid layout and a
#    disk twice the size sitting there to grow into.
disk="$(make_disk emmc.img)"
sysblock="$(fake_sysblock mmcblk1 0 131072)"
if run_grow mmcblk1 "$disk" "$sysblock" "$TMP/marker-emmc" >/dev/null 2>"$TMP/emmc.err"; then
    fail "mmcblk1 (eMMC) was not refused"
fi
grep -q "this is the box's eMMC" "$TMP/emmc.err" || fail "eMMC refusal message is missing"
[[ ! -f "$TMP/marker-emmc" ]] || fail "a refused run must not write the marker"

# 2. The real hardware case: an SD disk that is NOT mmcblk1, reporting
#    removable=0. Must proceed and actually grow the STORAGE partition.
#    partx -u needs a real block device to tell the kernel about, so this
#    one is loop-backed rather than a plain file.
disk_file="$(make_disk sd.img)"
disk="$(losetup --find --show "$disk_file")"
LOOP_DEVICES+=("$disk")
sysblock="$(fake_sysblock mmcblk0 0 131072)"
marker="$TMP/marker-sd"
out="$(run_grow mmcblk0 "$disk" "$sysblock" "$marker" 2>&1)" || { echo "$out" >&2; fail "removable=0 SD card was refused"; }
grep -q "proceeding anyway" <<<"$out" || fail "the removable=0 diagnostic was not logged"
grep -q "growing partition 4" <<<"$out" || fail "STORAGE partition was not grown"
[[ -f "$marker" ]] || fail "a successful run must write the marker"
new_size="$(sfdisk -J "$disk" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][3]["size"])')"
[[ "$new_size" -gt 4096 ]] || fail "STORAGE partition size did not increase (still $new_size sectors)"
[[ "$new_size" -eq $((131072 - 61440)) ]] || fail "STORAGE partition did not grow to fill the disk (got $new_size)"

# 3. Re-running with the marker present must be a no-op (idempotent):
#    no second growth attempt, no error.
out2="$(run_grow mmcblk0 "$disk" "$sysblock" "$marker" 2>&1)" || fail "a second run with the marker present must succeed"
[[ -z "$out2" ]] || fail "a marker-present run must do nothing (got: $out2)"

# 4. A disk whose table is not the A95X 4-partition layout is refused, even
#    when it is neither the eMMC nor short of space.
bad_disk="$TMP/bad.img"
truncate -s 32M "$bad_disk"
sfdisk --quiet --wipe always "$bad_disk" <<'EOF'
label: dos
unit: sectors
start=2048, size=8192, type=e
start=10240, size=32768, type=83
EOF
sysblock="$(fake_sysblock mmcblk0 0 131072)"
if run_grow mmcblk0 "$bad_disk" "$sysblock" "$TMP/marker-bad" >/dev/null 2>"$TMP/bad.err"; then
    fail "a non-A95X partition table was accepted"
fi
grep -q "not the A95X" "$TMP/bad.err" || fail "the wrong-layout refusal message is missing"

printf '%s\n' 'PASS: ashipaos-storage-grow E2E'
