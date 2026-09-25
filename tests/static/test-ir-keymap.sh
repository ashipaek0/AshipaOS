#!/usr/bin/env bash
# STATIC: the IR keymap is exactly what the generator derives from the stock
# firmware DTB, and Layer 1 installs it for the meson-ir receiver.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
command -v dtc >/dev/null || fail "dtc is required"
python3 -B "$ROOT/layers/layer1-rootfs/scripts/gen-ir-keymap.py" \
    "$ROOT/layers/layer2-image/files/a95x-f3-air/meson1.dtb" "$TMP/a95x-f3-air.toml"
cmp -s "$TMP/a95x-f3-air.toml" "$ROOT/rootfs-overlay/etc/rc_keymaps/a95x-f3-air.toml" \
    || fail "rootfs-overlay/etc/rc_keymaps/a95x-f3-air.toml differs from the generator output"
python3 - "$TMP/a95x-f3-air.toml" <<'PY' || fail "keymap lacks the navigation keys"
import sys, tomllib
codes = tomllib.load(open(sys.argv[1], "rb"))["protocols"][0]["scancodes"]
keys = set(codes.values())
assert {"KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT", "KEY_ENTER", "KEY_ESC", "KEY_MENU"} <= keys
assert codes["0xdf06"] == "KEY_ENTER" and codes["0xdf0a"] == "KEY_ESC"
PY
grep -q 'meson-ir \* a95x-f3-air.toml' "$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh" \
    || fail "Layer 1 must register the keymap for meson-ir in /etc/rc_maps.cfg"
printf '%s\n' 'IR keymap contract: PASS'
