#!/usr/bin/env bash
# Layer 2: build the chain-loaded mainline U-Boot (u-boot.ext) for the A95X.
# Verification Class: BUILD (CI; pinned source commit and tree, in-repo config)
#
# The box's vendor U-Boot loads this binary from the SD card and jumps to it;
# it then boots the Debian kernel. Its environment lives in RAM only
# (ENV_IS_NOWHERE), so it can never write the box's eMMC.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
PIN="$LAYER_DIR/config/u-boot/pin.json"
EVIDENCE_DIR="${ASHIPAOS_EVIDENCE_DIR:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output/evidence}"

log() { printf '[L2-UBOOT] %s\n' "$*" >&2; }
error() { printf '[L2-UBOOT ERROR] %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 ]] || { printf 'Usage: %s <output u-boot.bin>\n' "$(basename "$0")" >&2; exit 2; }
OUTPUT="$1"

mapfile -t pin < <(python3 - "$PIN" "$REPO_ROOT" <<'PY'
import json, pathlib, re, sys
pin = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
root = pathlib.Path(sys.argv[2])
assert pin["repository"] == "https://github.com/u-boot/u-boot.git"
assert re.fullmatch(r"v\d{4}\.\d{2}", pin["tag"])
for key in ("tag_object", "commit", "tree"):
    assert re.fullmatch(r"[0-9a-f]{40}", pin[key]), key
assert (root / pin["config_fragment"]).is_file()
for key in ("repository", "commit", "tree", "base_defconfig", "config_fragment", "device_tree", "text_base", "cross_compile"):
    print(pin[key])
PY
)
((${#pin[@]} == 8)) || error "invalid U-Boot pin: $PIN"
REPO_URL="${pin[0]}" COMMIT="${pin[1]}" TREE="${pin[2]}" DEFCONFIG="${pin[3]}"
FRAGMENT="$REPO_ROOT/${pin[4]}" DEVICE_TREE="${pin[5]}" TEXT_BASE="${pin[6]}"
export CROSS_COMPILE="${pin[7]}"
command -v "${CROSS_COMPILE}gcc" >/dev/null || error "missing cross compiler ${CROSS_COMPILE}gcc"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
SRC="$WORK/u-boot"
log "Fetching U-Boot $COMMIT"
git init -q "$SRC"
git -C "$SRC" fetch -q --depth 1 "$REPO_URL" "$COMMIT"
git -C "$SRC" checkout -q FETCH_HEAD
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$COMMIT" ]] || error "fetched commit does not match the pin"
[[ "$(git -C "$SRC" rev-parse 'HEAD^{tree}')" == "$TREE" ]] || error "fetched tree does not match the pin"

log "Configuring $DEFCONFIG + $(basename "$FRAGMENT")"
make -C "$SRC" -s "$DEFCONFIG"
(cd "$SRC" && scripts/kconfig/merge_config.sh -m .config "$FRAGMENT" >/dev/null)
make -C "$SRC" -s olddefconfig

# The safety-relevant options must have survived the merge.
config="$SRC/.config"
grep -qx "CONFIG_DEFAULT_DEVICE_TREE=\"$DEVICE_TREE\"" "$config" || error "device tree is not $DEVICE_TREE"
grep -qx "CONFIG_TEXT_BASE=$TEXT_BASE" "$config" || error "TEXT_BASE is not $TEXT_BASE"
grep -qx 'CONFIG_ENV_IS_NOWHERE=y' "$config" || error "environment must live in RAM only"
for forbidden in ENV_IS_IN_MMC CMD_DFU CMD_USB_MASS_STORAGE USB_GADGET CMD_GPT; do
    ! grep -qx "CONFIG_$forbidden=y" "$config" || error "CONFIG_$forbidden must be disabled"
done

log "Building u-boot.bin"
make -C "$SRC" -s -j"$(nproc)" u-boot.bin
grep -aq 'ashipaos-a95x-f3-air' "$SRC/u-boot.bin" || error "built binary lacks the AshipaOS identity"
mkdir -p "$(dirname "$OUTPUT")" "$EVIDENCE_DIR"
install -m 0644 "$SRC/u-boot.bin" "$OUTPUT"
cp "$config" "$EVIDENCE_DIR/u-boot.config"

python3 - "$EVIDENCE_DIR/u-boot.json" "$OUTPUT" "$PIN" "$("${CROSS_COMPILE}gcc" --version | head -1)" <<'PY'
import hashlib, json, pathlib, sys
out, binary, pin, compiler = sys.argv[1:]
data = pathlib.Path(binary).read_bytes()
json.dump({"component": "u-boot.ext", "pin": json.loads(pathlib.Path(pin).read_text()),
           "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
           "compiler": compiler, "config": "u-boot.config"},
          open(out, "w", encoding="utf-8"), indent=2)
PY
log "u-boot.ext: $OUTPUT ($(stat -c %s "$OUTPUT") bytes)"
