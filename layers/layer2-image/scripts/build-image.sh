#!/usr/bin/env bash
# Layer 2: A95X F3 Air removable-SD disk image.
# Verification Class: BUILD (CI only; VM and HARDWARE gates remain open)
#
# Builds a DOS/MBR image with a FAT16 boot partition (aml_autoscript, cfgload,
# Android legacy kernel.img, dtb.img) and an ext4 root partition, entirely from
# the Layer 1/5 rootfs tarball. Nothing is written before sector 8192, and no
# bootloader or eMMC payload is ever written.
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
Usage: $(basename "$0") [OPTIONS] <rootfs.tar.gz> [$TARGET]

Build the $TARGET SD image from the Layer 1/5 rootfs tarball (runs as root).

Options:
  -h, --help                 Show this help
  --validate                 Validate the configuration only
  --layout-only FILE         Write only the partition layout to FILE (test aid)

Dependencies: python3-yaml, util-linux (sfdisk), dosfstools, mtools,
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

boot, root = config["partitions"]["boot"], config["partitions"]["root"]
size_mb = config["image_size_mb"]
if config["partition_table"] != "dos":
    fail("partition_table must be dos")
if config["prepartition_gap"] != {"start_sector": 1, "end_sector": 8191, "contents": "zero"}:
    fail("the pre-partition gap must be sectors 1..8191, zero")
if config["raw_sd_payload_writes"] is not False:
    fail("raw SD payload writes are forbidden")
if (boot["start_sector"], boot["size_mb"], boot["filesystem"], boot["mbr_type"]) != (8192, 256, "fat16", "0x0e"):
    fail("boot partition must be FAT16 (0x0e), 256 MiB at sector 8192")
if root["start_sector"] != boot["start_sector"] + boot["size_mb"] * 2048:
    fail("root partition must directly follow the boot partition")
if (root["start_sector"], root["filesystem"], root["mbr_type"]) != (532480, "ext4", "0x83"):
    fail("root partition must be ext4 (0x83) at sector 532480")
if root["start_sector"] + root["size_mb"] * 2048 > size_mb * 2048:
    fail("partitions exceed image_size_mb")
if not re.fullmatch(r"[A-Z0-9_]{1,11}", boot["label"]) or not re.fullmatch(r"[A-Za-z0-9_-]{1,16}", root["label"]):
    fail("invalid filesystem label")
b = config["boot"]
if b["files"] != ["aml_autoscript", "cfgload", "kernel.img", "dtb.img", "manifest.json"]:
    fail("boot file set changed")
header = b["android_header"]
addresses = {k: int(header[k], 16) for k in ("kernel_base", "kernel_limit", "ramdisk_addr", "tags_addr")}
load_addr, dtb_addr = int(b["image_load_addr"], 16), int(b["dtb_addr"], 16)
if header["page_size"] != 2048 or addresses["kernel_base"] % 0x200000:
    fail("page size must be 2048 and the kernel base 2 MiB aligned")
if not addresses["kernel_limit"] <= addresses["ramdisk_addr"] < dtb_addr < load_addr:
    fail("kernel < ramdisk < dtb < kernel.img load address ordering is violated")
if f"root=LABEL={root['label']}" not in b["bootargs"] or "console=ttyAML0" not in b["bootargs"]:
    fail("bootargs must select the root label and the mainline ttyAML0 console")
dtb = target["mainline_boot"]["device_tree"]
if not re.fullmatch(r"amlogic/meson-[a-z0-9-]+\.dtb", dtb):
    fail(f"unexpected mainline DTB path: {dtb}")
values = {
    "IMAGE_SIZE_MB": size_mb,
    "BOOT_START": boot["start_sector"], "BOOT_SIZE_MB": boot["size_mb"], "BOOT_LABEL": boot["label"],
    "BOOT_TYPE": boot["mbr_type"][2:],
    "ROOT_START": root["start_sector"], "ROOT_SIZE_MB": root["size_mb"], "ROOT_LABEL": root["label"],
    "ROOT_TYPE": root["mbr_type"][2:],
    "PAGE_SIZE": header["page_size"], "KERNEL_BASE": header["kernel_base"],
    "KERNEL_LIMIT": header["kernel_limit"], "RAMDISK_ADDR": header["ramdisk_addr"],
    "TAGS_ADDR": header["tags_addr"], "IMAGE_LOAD_ADDR": b["image_load_addr"],
    "DTB_ADDR": b["dtb_addr"], "BOOTARGS": b["bootargs"], "MAINLINE_DTB": dtb,
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)" || error "configuration is invalid: $CONFIG_FILE"
    eval "$assignments"
    log "Layout: ${IMAGE_SIZE_MB} MiB; boot FAT16 ${BOOT_SIZE_MB} MiB @${BOOT_START}; root ext4 ${ROOT_SIZE_MB} MiB @${ROOT_START}"
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
start=$ROOT_START, size=$((ROOT_SIZE_MB * 2048)), type=$ROOT_TYPE
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

make_kernel_img() {
    local rootfs="$1" bootdir="$2" kernel initrd kver dtb
    kernel="$(rootfs_boot_file "$rootfs" vmlinuz vmlinuz)"
    initrd="$(rootfs_boot_file "$rootfs" initrd.img initrd.img)"
    kver="${kernel#/boot/vmlinuz-}"
    [[ "$initrd" == "/boot/initrd.img-$kver" ]] || error "kernel/initramfs version mismatch: $kernel $initrd"
    dtb="/usr/lib/linux-image-$kver/$MAINLINE_DTB"
    [[ -f "$rootfs$dtb" && ! -L "$rootfs$dtb" ]] || error "kernel package lacks the target DTB: $dtb"
    install -m 0644 "$rootfs$dtb" "$bootdir/dtb.img"
    printf '%s\n%s\n%s\n' "$kernel" "$initrd" "$dtb" >"$WORK_DIR/boot-sources"

    # Self-contained Android legacy v0 writer (Ubuntu's mkbootimg is broken).
    python3 - "$rootfs$kernel" "$rootfs$initrd" "$bootdir/kernel.img" "$WORK_DIR/kernel-img.json" \
        "$PAGE_SIZE" "$KERNEL_BASE" "$KERNEL_LIMIT" "$RAMDISK_ADDR" "$TAGS_ADDR" "$DTB_ADDR" "$BOOTARGS" <<'PY'
import gzip, hashlib, json, struct, sys
from pathlib import Path

kernel_path, ramdisk_path, out_path, info_path = sys.argv[1:5]
page, base, limit, ramdisk_addr, tags_addr, dtb_addr = (int(v, 0) for v in sys.argv[5:11])
cmdline = sys.argv[11].encode()

kernel = Path(kernel_path).read_bytes()
compression = "none"
if kernel[:2] == b"\x1f\x8b":
    # Vendor U-Boot bootm only reliably boots an uncompressed arm64 Image.
    kernel, compression = gzip.decompress(kernel), "gzip"
if len(kernel) < 64 or kernel[56:60] != b"ARM\x64":
    raise SystemExit("kernel is not an arm64 Image (missing ARM\\x64 magic)")
text_offset, image_size = struct.unpack_from("<QQ", kernel, 8)
image_size = image_size or len(kernel)
kernel_addr = base + text_offset
if kernel_addr + image_size > limit:
    raise SystemExit(f"kernel footprint 0x{kernel_addr + image_size:x} exceeds limit 0x{limit:x}")
ramdisk = Path(ramdisk_path).read_bytes()
if ramdisk_addr + len(ramdisk) > dtb_addr:
    raise SystemExit("initramfs would overlap the DTB load address")
if len(cmdline) >= 512:
    raise SystemExit("bootargs exceed the 512-byte Android header field")

header = bytearray(page)
header[:8] = b"ANDROID!"
# kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size,
# second_addr, tags_addr, page_size, header_version(0), os_version(0)
struct.pack_into("<10I", header, 8, len(kernel), kernel_addr, len(ramdisk), ramdisk_addr,
                 0, 0, tags_addr, page, 0, 0)
header[48:64] = b"AshipaOS-A95X".ljust(16, b"\0")
header[64:576] = cmdline.ljust(512, b"\0")
# Legacy ID: SHA-1 over each section followed by its size.
sha = hashlib.sha1()
for blob in (kernel, ramdisk, b""):
    sha.update(blob)
    sha.update(struct.pack("<I", len(blob)))
header[576:596] = sha.digest()

pad = lambda blob: blob + b"\0" * (-len(blob) % page)
Path(out_path).write_bytes(bytes(header) + pad(kernel) + pad(ramdisk))
Path(info_path).write_text(json.dumps({
    "format": "android-legacy-v0", "page_size": page,
    "kernel": {"source_compression": compression, "size": len(kernel), "text_offset": hex(text_offset),
               "image_size": hex(image_size), "load_addr": hex(kernel_addr),
               "sha256": hashlib.sha256(kernel).hexdigest()},
    "ramdisk": {"size": len(ramdisk), "load_addr": hex(ramdisk_addr),
                "sha256": hashlib.sha256(ramdisk).hexdigest()},
    "tags_addr": hex(tags_addr), "cmdline": cmdline.decode(),
}), encoding="utf-8")
PY
    [[ "$(head -c 8 "$bootdir/kernel.img")" == "ANDROID!" ]] || error "kernel.img has no Android header"
}

make_boot_scripts() {
    local bootdir="$1"
    command -v mkimage >/dev/null || error "u-boot-tools (mkimage) is required"
    # Run by the vendor U-Boot recovery path. The environment is reset in RAM
    # only; the environment is never persisted, because that would write eMMC.
    cat >"$WORK_DIR/aml_autoscript.txt" <<EOF
defenv
setenv ashipa_script_addr 0x01000000
setenv ashipa_img_addr $IMAGE_LOAD_ADDR
setenv dtb_mem_addr $DTB_ADDR
setenv device mmc
setenv devnr 0
setenv partnr 1
if fatload \${device} \${devnr}:\${partnr} \${ashipa_script_addr} cfgload; then autoscr \${ashipa_script_addr}; fi
EOF
    cat >"$WORK_DIR/cfgload.txt" <<EOF
setenv bootargs '$BOOTARGS'
fatload \${device} \${devnr}:\${partnr} \${dtb_mem_addr} dtb.img
fatload \${device} \${devnr}:\${partnr} \${ashipa_img_addr} kernel.img
bootm \${ashipa_img_addr}
EOF
    mkimage -A arm64 -O linux -T script -C none -n A95X-AUTOSCRIPT \
        -d "$WORK_DIR/aml_autoscript.txt" "$bootdir/aml_autoscript" >/dev/null
    mkimage -A arm64 -O linux -T script -C none -n A95X-CFGLOAD \
        -d "$WORK_DIR/cfgload.txt" "$bootdir/cfgload" >/dev/null
}

write_boot_manifest() {
    local bootdir="$1" rootfs_tar="$2"
    local sources
    mapfile -t sources <"$WORK_DIR/boot-sources"
    python3 - "$bootdir" "$WORK_DIR/kernel-img.json" "$rootfs_tar" "$TARGET" "$BOOT_LABEL" "$ROOT_LABEL" \
        "$BOOT_START" "$ROOT_START" "$IMAGE_LOAD_ADDR" "$DTB_ADDR" "${sources[@]}" <<'PY'
import hashlib, json, sys
from pathlib import Path
bootdir, info, rootfs_tar = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
target, boot_label, root_label, boot_start, root_start, load_addr, dtb_addr, kernel, initrd, dtb = sys.argv[4:14]
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = {
    "format": "ashipaos-a95x-boot-v2",
    "target": target,
    "partition": {"table": "dos", "start_sector": int(boot_start), "filesystem": "fat16", "label": boot_label},
    "root_partition": {"start_sector": int(root_start), "filesystem": "ext4", "label": root_label},
    "files": {name: digest(bootdir / name) for name in ("aml_autoscript", "cfgload", "kernel.img", "dtb.img")},
    "kernel_img": json.loads(info.read_text(encoding="utf-8")),
    "load_addresses": {"kernel_img": load_addr, "dtb": dtb_addr},
    "rootfs": {"archive_sha256": digest(rootfs_tar), "kernel": kernel, "initrd": initrd, "dtb": dtb},
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
    for name in aml_autoscript cfgload kernel.img dtb.img manifest.json; do
        mcopy -o -i "$fat" "$bootdir/$name" "::$name"
    done
    dd if="$fat" of="$image" bs=512 seek="$BOOT_START" conv=notrunc,sparse status=none
}

build_root_partition() {
    local image="$1" rootfs="$2" ext4="$WORK_DIR/root.ext4"
    printf 'LABEL=%s\t/\text4\tdefaults,noatime\t0\t1\n' "$ROOT_LABEL" >"$rootfs/etc/fstab"
    truncate -s "${ROOT_SIZE_MB}M" "$ext4"
    mkfs.ext4 -q -F -L "$ROOT_LABEL" -d "$rootfs" "$ext4"
    dd if="$ext4" of="$image" bs=512 seek="$ROOT_START" conv=notrunc,sparse status=none
}

write_metadata() {
    local image="$1" rootfs_tar="$2"
    python3 - "$image" "$rootfs_tar" "$TARGET" "$IMAGE_SIZE_MB" "$BOOT_SIZE_MB" "$BOOT_LABEL" \
        "$ROOT_SIZE_MB" "$ROOT_LABEL" "$EVIDENCE_DIR" "${GITHUB_RUN_ID:-local}" \
        "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)" <<'PY'
import hashlib, json, os, sys, time
image, rootfs_tar, target, size_mb, boot_mb, boot_label, root_mb, root_label, evidence_dir, run_id, commit = sys.argv[1:]
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
meta = {
    "image_type": "disk_image", "target": target, "total_size_mb": int(size_mb),
    "partition_table": "dos",
    "partitions": {"boot": {"size_mb": int(boot_mb), "type": "fat16", "label": boot_label},
                   "root": {"size_mb": int(root_mb), "type": "ext4", "label": root_label, "mount": "/"}},
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
    local rootfs_tar="$1" rootfs bootdir final_image
    for cmd in sfdisk mkfs.fat mcopy mkfs.ext4 mkimage python3 tar; do
        command -v "$cmd" >/dev/null || error "missing dependency: $cmd"
    done
    [[ -f "$rootfs_tar" ]] || error "rootfs tarball not found: $rootfs_tar"
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

    make_kernel_img "$rootfs" "$bootdir"
    make_boot_scripts "$bootdir"
    write_boot_manifest "$bootdir" "$rootfs_tar"

    PARTIAL_IMAGE="$final_image.partial"
    create_partition_layout "$PARTIAL_IMAGE"
    build_boot_partition "$PARTIAL_IMAGE" "$bootdir"
    build_root_partition "$PARTIAL_IMAGE" "$rootfs"
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
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        usage >&2
        exit 2
    fi
    [[ "${2:-$TARGET}" == "$TARGET" ]] || error "unsupported target: $2"
    if [[ $EUID -ne 0 ]]; then
        # Root keeps rootfs ownership intact while the ext4 tree is staged.
        exec sudo --preserve-env=GITHUB_WORKSPACE,GITHUB_RUN_ID,RUNNER_TEMP,ASHIPAOS_IMAGE_CONFIG,ASHIPAOS_IMAGE_DIR,ASHIPAOS_EVIDENCE_DIR \
            bash "${BASH_SOURCE[0]}" "$@"
    fi
    load_config
    build_image "$1"
}

main "$@"
