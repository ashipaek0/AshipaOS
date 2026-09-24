#!/usr/bin/env bash
# Layer 2 STATIC: configuration validates and the builder can never write to a
# device, eMMC, or the U-Boot environment.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer2-image"
SCRIPT="$LAYER/scripts/build-image.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$SCRIPT"
bash "$SCRIPT" --validate >/dev/null 2>&1 || fail "image-config.yaml does not validate"
! grep -Eq 'of=/dev/|saveenv|mmc write|losetup|guestfish' "$SCRIPT" || fail "builder writes devices, eMMC or the U-Boot environment"
python3 - "$LAYER/files/a95x-f3-air" <<'PY'
import hashlib, json, pathlib, sys
d = pathlib.Path(sys.argv[1])
provenance = json.loads((d / "provenance.json").read_text(encoding="utf-8"))
for name, facts in provenance["stock_inputs"].items():
    if hashlib.sha256((d / name).read_bytes()).hexdigest() != facts["sha256"]:
        raise SystemExit(f"stock input {name} does not match its recorded SHA-256")
PY
# Chain-loaded mainline U-Boot: pinned source, RAM-only environment, no
# eMMC-writing tools, and the same mainline DTB the kernel boots.
UBOOT_BUILD="$LAYER/scripts/build-u-boot.sh"
bash -n "$UBOOT_BUILD"
python3 - "$LAYER/config/u-boot" "$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml" <<'PY' || fail "U-Boot pin or config fragment is unsafe or inconsistent"
import json, pathlib, re, sys, yaml
d = pathlib.Path(sys.argv[1])
pin = json.loads((d / "pin.json").read_text())
target = yaml.safe_load(open(sys.argv[2]))
assert pin["repository"] == "https://github.com/u-boot/u-boot.git" and re.fullmatch(r"v\d{4}\.\d{2}", pin["tag"])
assert all(re.fullmatch(r"[0-9a-f]{40}", pin[k]) for k in ("tag_object", "commit", "tree"))
frag = (d / "a95x-f3-air.config").read_text().splitlines()
dtb = target["mainline_boot"]["device_tree"]
assert f'CONFIG_DEFAULT_DEVICE_TREE="{dtb[:-len(".dtb")]}"' in frag and pin["device_tree"] + ".dtb" == dtb
for required in ("CONFIG_ENV_IS_NOWHERE=y", "# CONFIG_ENV_IS_IN_MMC is not set", "# CONFIG_CMD_DFU is not set",
                 "# CONFIG_USB_GADGET is not set", "CONFIG_FAT_WRITE=y"):
    assert required in frag, required
boot = next(l for l in frag if l.startswith("CONFIG_BOOTCOMMAND="))
assert "ashipaos.id" in boot and "saveenv" not in boot
PY
grep -q 'fatload mmc 0:1 $UBOOT_EXT_ADDR u-boot.ext; then go $UBOOT_EXT_ADDR; fi' "$SCRIPT" || fail "entry scripts must chain-load u-boot.ext in one statement"
printf '%s\n' 'A95X Layer 2 static contract: PASS'
