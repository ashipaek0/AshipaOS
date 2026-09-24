#!/usr/bin/env bash
set -Eeuo pipefail
iso=${1:?ISO path}; command -v xorriso >/dev/null || { echo xorriso required >&2; exit 1; }; command -v mdir >/dev/null || { echo mtools required >&2; exit 1; }; command -v zstd >/dev/null || { echo zstd required >&2; exit 1; }; [[ -s "$iso" ]] || exit 1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
xorriso -indev "$iso" -report_el_torito plain > "$tmp/report" 2>/dev/null
xorriso -osirrox on -indev "$iso" -extract / "$tmp/tree" >/dev/null 2>&1
template=/usr/lib/grub/i386-pc/boot_hybrid.img
[[ -s "$template" ]] || { echo "GRUB boot_hybrid.img missing: $template" >&2; exit 1; }
python3 "$(dirname "$0")/validate-iso-tree.py" "$tmp/report" "$tmp/tree" "$iso" "$template"
