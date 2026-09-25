#!/usr/bin/env bash
# Layer 2: A95X F3 Air removable-SD disk image.
# Verification Class: BUILD (CI only; VM and HARDWARE gates remain open)
#
# Builds a DOS/MBR image with a FAT16 boot partition (vendor-U-Boot entry
# scripts, the chain-loaded mainline U-Boot, boot.scr, per-slot kernel /
# initramfs / DTB), two ext4 root slots (A/B, see contracts/os-ota.md for the
# update-and-rollback contract they exist for) and an ext4 STORAGE partition
# for settings and app state, shared by both slots. Nothing is written before
# sector 8192, and nothing ever writes the box's eMMC.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
CONFIG_FILE="${ASHIPAOS_IMAGE_CONFIG:-$LAYER_DIR/config/image-config.yaml}"
TARGET="a95x-f3-air"
TARGET_FILE="$REPO_ROOT/build/targets/amlogic/boxes/$TARGET.yaml"
OUTPUT_DIR="${ASHIPAOS_IMAGE_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output/images}"
EVIDENCE_DIR="${ASHIPAOS_EVIDENCE_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output/evidence}"
WORK_DIR=""
PARTIAL_IMAGE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <rootfs.tar.gz> <u-boot.bin> [$TARGET]

Build the $TARGET SD image from the Layer 1/5 rootfs tarball and the
chain-loaded mainline U-Boot from build-u-boot.sh (runs as root). The rootfs
becomes root slot A; slot B is created empty, ready for an OS update
(contracts/os-ota.md) to install into without touching slot A or STORAGE.

Options:
  -h, --help                 Show this help
  --validate                 Validate the configuration only
  --layout-only FILE         Write only the partition layout to FILE (test aid)

Dependencies: python3-yaml, util-linux (sfdisk, partx), dosfstools, mtools,
              e2fsprogs (mkfs.ext4 -d), u-boot-tools (mkimage)
EOF
}

log() { printf '[L2-IMAGE] %(%Y-%m-%d %H:%M:%S)T %s\n' -1 "$*" >&2; }
error() { printf '[L2-IMAGE ERROR] %s\n' "$*" >&2; exit 1; }

cleanup() {
    local status=$?
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf --one-file-system -- "$WORK_DIR"
    [[ -n "$PARTIAL_IMAGE" ]] && rm -f -- "$PARTIAL_IMAGE"
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Reads and validates image-config.yaml plus the target's mainline DTB, and
# prints shell assignments. Every layout invariant of the contract is enforced
# here, so --validate and --layout-only exercise the same checks as a build.
load_config() {
    local assignments
    assignments="$(python3 - "$CONFIG_FILE" "$TARGET_FILE" <<'PY'
import re, shlex, sys
import yaml

config = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
target = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))

def fail(message):
    raise SystemExit(f"image-config: {message}")

parts = config["partitions"]
boot, root_a, root_b, storage = parts["boot"], parts["root_a"], parts["root_b"], parts["storage"]
size_mb = config["image_size_mb"]
if config["partition_table"] != "dos":
    fail("partition_table must be dos")
if config["prepartition_gap"] != {"start_sector": 1, "end_sector": 8191, "contents": "zero"}:
    fail("the pre-partition gap must be sectors 1..8191, zero")
if config["raw_sd_payload_writes"] is not False:
    fail("raw SD payload writes are forbidden")
if (boot["start_sector"], boot["size_mb"], boot["filesystem"], boot["mbr_type"]) != (8192, 256, "fat16", "0x0e"):
    fail("boot partition must be FAT16 (0x0e), 256 MiB at sector 8192")

label_re = re.compile(r"[A-Za-z0-9_-]{1,16}")
end = boot["start_sector"] + boot["size_mb"] * 2048
for name, part in (("root_a", root_a), ("root_b", root_b), ("storage", storage)):
    if part["start_sector"] != end:
        fail(f"{name} must directly follow the previous partition (expected start_sector {end})")
    if (part["filesystem"], part["mbr_type"]) != ("ext4", "0x83"):
        fail(f"{name} must be ext4 (0x83)")
    if not label_re.fullmatch(part["label"]):
        fail(f"{name}: invalid filesystem label")
    end += part["size_mb"] * 2048
if end > size_mb * 2048:
    fail("partitions exceed image_size_mb")
if not re.fullmatch(r"[A-Z0-9_]{1,11}", boot["label"]):
    fail("invalid boot filesystem label")
if root_a["label"] == root_b["label"] or storage["label"] in (root_a["label"], root_b["label"]):
    fail("root_a, root_b and storage must have distinct labels")

b = config["boot"]
if b["entry_scripts"] != ["aml_autoscript", "cfgload", "s905_autoscript"]:
    fail("vendor U-Boot entry scripts changed")
if b["files"] != ["ashipaos.id", "u-boot.ext", "boot.scr", "active-root.txt", "manifest.json"]:
    fail("boot file set changed")
if b["per_slot_files"] != ["Image", "initrd.img"]:
    fail("per-slot boot file set changed")
if int(b["u_boot_ext_addr"], 16) != 0x01000000:
    fail("u-boot.ext must load at mainline U-Boot's TEXT_BASE 0x01000000")
if not 0x02000000 <= int(b["log_addr"], 16) < 0x05000000:
    fail("log_addr must stay clear of u-boot.ext and the secure-monitor carve-out")
if not isinstance(b["max_boot_tries"], int) or not 1 <= b["max_boot_tries"] <= 10:
    fail("max_boot_tries must be a small positive integer")
# The active root's LABEL= is assembled dynamically by boot.scr from
# active-root.txt; a static root= here would silently override that.
if "root=" in b["bootargs"] or "rootwait" not in b["bootargs"] or "console=ttyAML0" not in b["bootargs"]:
    fail("bootargs must not set root= statically and must select the mainline ttyAML0 console")
dtb = target["mainline_boot"]["device_tree"]
if not re.fullmatch(r"amlogic/meson-[a-z0-9-]+[.]dtb", dtb):
    fail(f"unexpected mainline DTB path: {dtb}")
values = {
    "IMAGE_SIZE_MB": size_mb,
    "BOOT_START": boot["start_sector"], "BOOT_SIZE_MB": boot["size_mb"], "BOOT_LABEL": boot["label"],
    "BOOT_TYPE": boot["mbr_type"][2:],
    "ROOT_A_START": root_a["start_sector"], "ROOT_A_SIZE_MB": root_a["size_mb"], "ROOT_A_LABEL": root_a["label"],
    "ROOT_B_START": root_b["start_sector"], "ROOT_B_SIZE_MB": root_b["size_mb"], "ROOT_B_LABEL": root_b["label"],
    "ROOT_TYPE": root_a["mbr_type"][2:],
    "STORAGE_START": storage["start_sector"], "STORAGE_SIZE_MB": storage["size_mb"],
    "STORAGE_LABEL": storage["label"], "STORAGE_TYPE": storage["mbr_type"][2:],
    "UBOOT_EXT_ADDR": b["u_boot_ext_addr"], "LOG_ADDR": b["log_addr"], "MAX_BOOT_TRIES": b["max_boot_tries"],
    "BOOTARGS": b["bootargs"], "MAINLINE_DTB": dtb,
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)" || error "configuration is invalid: $CONFIG_FILE"
    eval "$assignments"
    log "Layout: ${IMAGE_SIZE_MB} MiB; boot FAT16 ${BOOT_SIZE_MB} MiB @${BOOT_START};" \
        "root-a ext4 ${ROOT_A_SIZE_MB} MiB @${ROOT_A_START}; root-b ext4 ${ROOT_B_SIZE_MB} MiB @${ROOT_B_START};" \
        "storage ext4 ${STORAGE_SIZE_MB} MiB @${STORAGE_START}"
}

make_work_dir() {
    local parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    WORK_DIR="$(mktemp -d "$parent/ashipaos-image.XXXXXX")"
}

create_partition_layout() {
    local image="$1"
    command -v sfdisk >/dev/null || error "sfdisk is required (util-linux/fdisk)"
    truncate -s "${IMAGE_SIZE_MB}M" "$image"
    sfdisk --quiet --wipe always "$image" <<EOF
label: dos
unit: sectors
sector-size: 512

start=$BOOT_START, size=$((BOOT_SIZE_MB * 2048)), type=$BOOT_TYPE, bootable
start=$ROOT_A_START, size=$((ROOT_A_SIZE_MB * 2048)), type=$ROOT_TYPE
start=$ROOT_B_START, size=$((ROOT_B_SIZE_MB * 2048)), type=$ROOT_TYPE
start=$STORAGE_START, size=$((STORAGE_SIZE_MB * 2048)), type=$STORAGE_TYPE
EOF
    sfdisk --verify "$image" >/dev/null
}

# Resolve a Debian top-level link (/vmlinuz, /initrd.img) strictly inside the
# extracted rootfs: the link must point at a regular file directly in /boot.
rootfs_boot_file() {
    local rootfs="$1" link="$2" prefix="$3" target
    [[ -L "$rootfs/$link" ]] || error "rootfs /$link is not a symlink"
    target="$(readlink "$rootfs/$link")"
    target="/${target#/}"
    [[ "$target" =~ ^/boot/${prefix//./\\.}-[A-Za-z0-9.+_~-]+$ ]] || error "rootfs /$link points outside /boot: $target"
    [[ -f "$rootfs$target" && ! -L "$rootfs$target" && -s "$rootfs$target" ]] ||
        error "rootfs $target is not a regular, non-empty file"
    printf '%s\n' "$target"
}

# Stage the kernel (as a raw arm64 Image), initramfs and mainline DTB for one
# root slot, from one rootfs; nothing is taken from the build host.
stage_kernel() {
    local rootfs="$1" bootdir="$2" slot="$3" kernel initrd kver dtb dtb_base
    kernel="$(rootfs_boot_file "$rootfs" vmlinuz vmlinuz)"
    initrd="$(rootfs_boot_file "$rootfs" initrd.img initrd.img)"
    kver="${kernel#/boot/vmlinuz-}"
    [[ "$initrd" == "/boot/initrd.img-$kver" ]] || error "kernel/initramfs version mismatch: $kernel $initrd"
    dtb="/usr/lib/linux-image-$kver/$MAINLINE_DTB"
    [[ -f "$rootfs$dtb" && ! -L "$rootfs$dtb" ]] || error "kernel package lacks the target DTB: $dtb"
    dtb_base="$(basename "$MAINLINE_DTB" .dtb)"
    install -m 0644 "$rootfs$dtb" "$bootdir/$dtb_base-$slot.dtb"
    install -m 0644 "$rootfs$initrd" "$bootdir/initrd.img-$slot"
    printf '%s\n%s\n%s\n' "$kernel" "$initrd" "$dtb" >"$WORK_DIR/boot-sources-$slot"
    python3 - "$rootfs$kernel" "$bootdir/Image-$slot" <<'PY'
import gzip, sys
from pathlib import Path
kernel = Path(sys.argv[1]).read_bytes()
if kernel[:2] == b"\x1f\x8b":
    kernel = gzip.decompress(kernel)
if len(kernel) < 64 or kernel[56:60] != b"ARM\x64":
    raise SystemExit("kernel is not an arm64 Image (missing ARM64 magic)")
Path(sys.argv[2]).write_bytes(kernel)
PY
}

# Script run by vendor U-Boot through any of the entry names: record that it
# ran (on the SD card's own FAT partition), then jump to mainline U-Boot. The
# load and the jump are one statement, so overwriting the running script's
# buffer cannot matter. The environment is never persisted (that would write
# eMMC).
vendor_entry_script() {
    local entry="$1"
    cat <<EOF
echo AshipaOS: vendor U-Boot entered through $entry
setenv ashipa_stage vendor-u-boot:$entry
env export -t $LOG_ADDR ashipa_stage bootcmd loadaddr
fatwrite mmc 0:1 $LOG_ADDR ashipaos-stage1-vendor.txt \${filesize}
if fatload mmc 0:1 $UBOOT_EXT_ADDR u-boot.ext; then go $UBOOT_EXT_ADDR; fi
echo AshipaOS: could not load u-boot.ext
EOF
}

# Run by mainline U-Boot (u-boot.ext) from this card, found by ashipaos.id.
# Reads active-root.txt to choose slot A or B, applies the boot-tries/revert
# protocol from contracts/os-ota.md entirely inside U-Boot (so it works even
# if the selected slot's kernel never reaches Linux), then boots that slot.
boot_scr_script() {
    local dtb_base
    dtb_base="$(basename "$MAINLINE_DTB" .dtb)"
    cat <<EOF
echo AshipaOS: mainline U-Boot booting from mmc \${ashipa_dev}
setenv ashipa_part mmc \${ashipa_dev}:1
setenv active_root a
setenv pending 0
setenv boot_tries 0
if fatload \${ashipa_part} $LOG_ADDR active-root.txt; then env import -t $LOG_ADDR \${filesize}; fi
if test "\${pending}" = "1"; then
    setexpr boot_tries \${boot_tries} + 1
    if test \${boot_tries} -ge $MAX_BOOT_TRIES; then
        echo AshipaOS: slot \${active_root} did not confirm after \${boot_tries} attempts, reverting
        if test "\${active_root}" = "a"; then setenv active_root b; else setenv active_root a; fi
        setenv pending 0
        setenv boot_tries 0
    fi
    env export -t $LOG_ADDR active_root pending boot_tries
    fatwrite \${ashipa_part} $LOG_ADDR active-root.txt \${filesize}
fi
if test "\${active_root}" = "b"; then setenv root_label $ROOT_B_LABEL; else setenv root_label $ROOT_A_LABEL; fi
echo AshipaOS: booting slot \${active_root} (\${root_label}), pending=\${pending} tries=\${boot_tries}
setenv ashipa_stage mainline-u-boot
setenv bootargs "root=LABEL=\${root_label} $BOOTARGS"
env export -t $LOG_ADDR ashipa_stage ashipa_dev ver fdtfile bootargs active_root pending boot_tries kernel_addr_r ramdisk_addr_r fdt_addr_r
fatwrite \${ashipa_part} $LOG_ADDR ashipaos-stage2-u-boot.txt \${filesize}
load \${ashipa_part} \${kernel_addr_r} Image-\${active_root} || echo AshipaOS: failed to load Image-\${active_root}
load \${ashipa_part} \${fdt_addr_r} $dtb_base-\${active_root}.dtb || echo AshipaOS: failed to load $dtb_base-\${active_root}.dtb
load \${ashipa_part} \${ramdisk_addr_r} initrd.img-\${active_root} || echo AshipaOS: failed to load initrd.img-\${active_root}
booti \${kernel_addr_r} \${ramdisk_addr_r}:\${filesize} \${fdt_addr_r}
setenv ashipa_stage mainline-u-boot-booti-failed
env export -t $LOG_ADDR ashipa_stage active_root
fatwrite \${ashipa_part} $LOG_ADDR ashipaos-stage2-u-boot-failed.txt \${filesize}
echo AshipaOS: booti returned, see ashipaos-stage2-u-boot-failed.txt on the SD card
EOF
}

make_boot_scripts() {
    local bootdir="$1" entry
    command -v mkimage >/dev/null || error "u-boot-tools (mkimage) is required"
    for entry in aml_autoscript cfgload s905_autoscript; do
        vendor_entry_script "$entry" >"$WORK_DIR/$entry.txt"
        mkimage -A arm64 -O linux -T script -C none -n "AshipaOS $entry" \
            -d "$WORK_DIR/$entry.txt" "$bootdir/$entry" >/dev/null
    done
    boot_scr_script >"$WORK_DIR/boot.cmd"
    mkimage -A arm64 -O linux -T script -C none -n "AshipaOS boot.scr" \
        -d "$WORK_DIR/boot.cmd" "$bootdir/boot.scr" >/dev/null
    printf 'AshipaOS %s boot card\n' "$TARGET" >"$bootdir/ashipaos.id"
    # A fresh flash always boots slot A; slot B is empty until an OS update
    # (contracts/os-ota.md) installs into it. Never itself pending/counted.
    printf 'active_root=a\npending=0\nboot_tries=0\n' >"$bootdir/active-root.txt"
}

write_boot_manifest() {
    local bootdir="$1" rootfs_tar="$2" dtb_base sources
    dtb_base="$(basename "$MAINLINE_DTB" .dtb)"
    mapfile -t sources <"$WORK_DIR/boot-sources-a"
    python3 - "$bootdir" "$rootfs_tar" "$TARGET" "$BOOT_LABEL" "$ROOT_A_LABEL" "$ROOT_B_LABEL" "$STORAGE_LABEL" \
        "$BOOT_START" "$ROOT_A_START" "$ROOT_B_START" "$STORAGE_START" \
        "$UBOOT_EXT_ADDR" "$BOOTARGS" "$MAX_BOOT_TRIES" "$dtb_base" "${sources[@]}" <<'PY'
import hashlib, json, sys
from pathlib import Path
bootdir, rootfs_tar = Path(sys.argv[1]), Path(sys.argv[2])
(target, boot_label, root_a_label, root_b_label, storage_label, boot_start, root_a_start, root_b_start,
 storage_start, ext_addr, bootargs, max_tries, dtb_base, kernel, initrd, dtb) = sys.argv[3:19]
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
names = ["aml_autoscript", "cfgload", "s905_autoscript", "u-boot.ext", "boot.scr", "ashipaos.id",
         "active-root.txt", f"Image-a", f"initrd.img-a", f"{dtb_base}-a.dtb"]
manifest = {
    "format": "ashipaos-a95x-boot-v4",
    "target": target,
    "chain": ["vendor U-Boot (eMMC, untouched)", "entry script", "u-boot.ext (mainline)",
              "boot.scr (active-root.txt slot selection)", "booti"],
    "partition": {"table": "dos", "start_sector": int(boot_start), "filesystem": "fat16", "label": boot_label},
    "root_partitions": {
        "a": {"start_sector": int(root_a_start), "filesystem": "ext4", "label": root_a_label, "populated": True},
        "b": {"start_sector": int(root_b_start), "filesystem": "ext4", "label": root_b_label, "populated": False},
    },
    "storage_partition": {"start_sector": int(storage_start), "filesystem": "ext4", "label": storage_label},
    "files": {name: digest(bootdir / name) for name in names},
    "u_boot_ext_addr": ext_addr,
    "bootargs_template": bootargs,
    "max_boot_tries": int(max_tries),
    "active_root": "a",
    "rootfs": {"archive_sha256": digest(rootfs_tar), "kernel": kernel, "initrd": initrd, "dtb": dtb},
    "diagnostics": ["ashipaos-stage1-vendor.txt", "ashipaos-stage2-u-boot.txt", "ashipaos-stage3-linux.txt"],
    "provenance": "layers/layer2-image/files/a95x-f3-air/provenance.json",
    "hardware_claim": "none; physical boot is unverified",
}
(bootdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
}

build_boot_partition() {
    local image="$1" bootdir="$2" fat="$WORK_DIR/boot.fat" name
    truncate -s "${BOOT_SIZE_MB}M" "$fat"
    mkfs.fat -F 16 -S 512 -n "$BOOT_LABEL" "$fat" >/dev/null
    export MTOOLS_SKIP_CHECK=1
    for name in "$bootdir"/*; do
        mcopy -o -i "$fat" "$name" "::$(basename "$name")"
    done
    dd if="$fat" of="$image" bs=512 seek="$BOOT_START" conv=notrunc,sparse status=none
}

# Root fstab: no `/` entry (the kernel cmdline mounts root; a fixed label here
# would be wrong for whichever slot booted). STORAGE is shared by both slots
# and grown to fill the SD card by ashipaos-storage-grow.service before it is
# ever mounted (x-systemd.requires); ashipaos-storage-grow.service is
# installed by Layer 1 into every root slot.
write_shared_fstab() {
    local rootfs="$1"
    {
        printf 'LABEL=%s\t/boot/firmware\tvfat\tdefaults,nofail,umask=0022\t0\t0\n' "$BOOT_LABEL"
        printf 'LABEL=%s\t/storage\text4\tdefaults,noatime,nofail,x-systemd.growfs,x-systemd.requires=ashipaos-storage-grow.service\t0\t2\n' \
            "$STORAGE_LABEL"
    } >"$rootfs/etc/fstab"
    mkdir -p "$rootfs/boot/firmware" "$rootfs/storage"
}

build_root_partition_a() {
    local image="$1" rootfs="$2" ext4="$WORK_DIR/root-a.ext4"
    write_shared_fstab "$rootfs"
    truncate -s "${ROOT_A_SIZE_MB}M" "$ext4"
    mkfs.ext4 -q -F -L "$ROOT_A_LABEL" -d "$rootfs" "$ext4"
    dd if="$ext4" of="$image" bs=512 seek="$ROOT_A_START" conv=notrunc,sparse status=none
}

# Slot B starts empty: nothing boots it until an OS update installs into it.
build_root_partition_b() {
    local image="$1" ext4="$WORK_DIR/root-b.ext4"
    truncate -s "${ROOT_B_SIZE_MB}M" "$ext4"
    mkfs.ext4 -q -F -L "$ROOT_B_LABEL" "$ext4"
    dd if="$ext4" of="$image" bs=512 seek="$ROOT_B_START" conv=notrunc,sparse status=none
}

# STORAGE starts small and empty; ashipaos-storage-grow.service claims the
# rest of the real SD card on first boot (the base image is a few GB; SD cards
# sold for this box are typically far larger).
build_storage_partition() {
    local image="$1" ext4="$WORK_DIR/storage.ext4"
    truncate -s "${STORAGE_SIZE_MB}M" "$ext4"
    mkfs.ext4 -q -F -L "$STORAGE_LABEL" "$ext4"
    dd if="$ext4" of="$image" bs=512 seek="$STORAGE_START" conv=notrunc,sparse status=none
}

write_metadata() {
    local image="$1" rootfs_tar="$2"
    python3 - "$image" "$rootfs_tar" "$TARGET" "$IMAGE_SIZE_MB" "$BOOT_SIZE_MB" "$BOOT_LABEL" \
        "$ROOT_A_SIZE_MB" "$ROOT_A_LABEL" "$ROOT_B_SIZE_MB" "$ROOT_B_LABEL" "$STORAGE_SIZE_MB" "$STORAGE_LABEL" \
        "$EVIDENCE_DIR" "${GITHUB_RUN_ID:-local}" \
        "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)" <<'PY'
import hashlib, json, os, sys, time
(image, rootfs_tar, target, size_mb, boot_mb, boot_label, root_a_mb, root_a_label, root_b_mb, root_b_label,
 storage_mb, storage_label, evidence_dir, run_id, commit) = sys.argv[1:]
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
meta = {
    "image_type": "disk_image", "target": target, "total_size_mb": int(size_mb),
    "partition_table": "dos",
    "partitions": {
        "boot": {"size_mb": int(boot_mb), "type": "fat16", "label": boot_label},
        "root_a": {"size_mb": int(root_a_mb), "type": "ext4", "label": root_a_label, "populated": True},
        "root_b": {"size_mb": int(root_b_mb), "type": "ext4", "label": root_b_label, "populated": False},
        "storage": {"size_mb": int(storage_mb), "type": "ext4", "label": storage_label, "mount": "/storage"},
    },
    "active_root": "a",
    "bootloader": "stock vendor U-Boot on eMMC (not in image); SD boot via aml_autoscript",
    "image": os.path.basename(image), "image_sha256": digest(image),
    "rootfs_sha256": digest(rootfs_tar),
    "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
with open(image + ".meta.json", "w", encoding="utf-8") as stream:
    json.dump(meta, stream, indent=2)
    stream.write("\n")
os.makedirs(evidence_dir, exist_ok=True)
evidence = {"layer": 2, "task_id": "layer2-a95x-sd-image", "verification_class": "BUILD",
            "result": "PASS", "commit_sha": commit, "ci_run_id": run_id,
            "blocked_gates": ["VM", "HARDWARE"], **meta}
with open(os.path.join(evidence_dir, "layer2-image.json"), "w", encoding="utf-8") as stream:
    json.dump(evidence, stream, indent=2)
    stream.write("\n")
PY
}

build_image() {
    local rootfs_tar="$1" uboot="$2" rootfs bootdir final_image
    for cmd in sfdisk mkfs.fat mcopy mkfs.ext4 mkimage python3 tar; do
        command -v "$cmd" >/dev/null || error "missing dependency: $cmd"
    done
    [[ -f "$rootfs_tar" ]] || error "rootfs tarball not found: $rootfs_tar"
    [[ -s "$uboot" ]] || error "u-boot.bin not found: $uboot"
    grep -aq 'ashipaos-a95x-f3-air' "$uboot" || error "$uboot is not the AshipaOS A95X U-Boot build"
    rootfs_tar="$(realpath "$rootfs_tar")"
    mkdir -p "$OUTPUT_DIR"
    final_image="$OUTPUT_DIR/ashipaos-$TARGET-$(date -u +%Y%m%d).img"
    [[ ! -e "$final_image" ]] || error "refusing to overwrite $final_image"

    make_work_dir
    rootfs="$WORK_DIR/rootfs"
    bootdir="$WORK_DIR/boot"
    mkdir -p "$rootfs" "$bootdir"
    log "Extracting $rootfs_tar"
    tar -C "$rootfs" --numeric-owner --xattrs --acls -xpzf "$rootfs_tar"

    stage_kernel "$rootfs" "$bootdir" a
    install -m 0644 "$uboot" "$bootdir/u-boot.ext"
    # User-editable Wi-Fi template; imported and wiped on first boot.
    install -m 0644 "$rootfs/usr/share/ashipaos/wifi.txt" "$bootdir/wifi.txt"
    make_boot_scripts "$bootdir"
    write_boot_manifest "$bootdir" "$rootfs_tar"

    PARTIAL_IMAGE="$final_image.partial"
    create_partition_layout "$PARTIAL_IMAGE"
    build_boot_partition "$PARTIAL_IMAGE" "$bootdir"
    build_root_partition_a "$PARTIAL_IMAGE" "$rootfs"
    build_root_partition_b "$PARTIAL_IMAGE"
    build_storage_partition "$PARTIAL_IMAGE"
    mv -f -- "$PARTIAL_IMAGE" "$final_image"
    PARTIAL_IMAGE=""
    write_metadata "$final_image" "$rootfs_tar"

    # shellcheck source=scripts/rootfs-ownership.sh
    source "$REPO_ROOT/scripts/rootfs-ownership.sh"
    rootfs_output_owner "$final_image" "$final_image.meta.json" "$OUTPUT_DIR" \
        "$EVIDENCE_DIR" "$EVIDENCE_DIR/layer2-image.json" || error "could not restore output ownership"
    log "Layer 2 build complete: $final_image"
    printf '%s\n' "$final_image"
}

main() {
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        --validate)
            [[ $# -eq 1 ]] || error "--validate takes no arguments"
            load_config
            return 0 ;;
        --layout-only)
            [[ $# -eq 2 ]] || error "--layout-only requires exactly one output file"
            load_config
            PARTIAL_IMAGE="$2"
            create_partition_layout "$2"
            PARTIAL_IMAGE=""
            return 0 ;;
    esac
    if [[ $# -lt 2 || $# -gt 3 ]]; then
        usage >&2
        exit 2
    fi
    [[ "${3:-$TARGET}" == "$TARGET" ]] || error "unsupported target: $3"
    if [[ $EUID -ne 0 ]]; then
        # Root keeps rootfs ownership intact while the ext4 tree is staged.
        exec sudo --preserve-env=GITHUB_WORKSPACE,GITHUB_RUN_ID,RUNNER_TEMP,ASHIPAOS_IMAGE_CONFIG,ASHIPAOS_IMAGE_DIR,ASHIPAOS_EVIDENCE_DIR \
            bash "${BASH_SOURCE[0]}" "$@"
    fi
    load_config
    build_image "$1" "$2"
}

main "$@"
