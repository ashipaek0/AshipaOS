#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/in" "$tmp/target"
printf 'payload' > "$tmp/in/appliance.img.zst"
size=$(stat -c %s "$tmp/in/appliance.img.zst"); hash=$(sha256sum "$tmp/in/appliance.img.zst" | cut -d' ' -f1)
printf 'sha256=%s\nsize=%s\n' "$hash" "$size" > "$tmp/in/appliance.img.manifest"
case "$mode" in
  corrupt) printf 'sha256=%064d\nsize=%s\n' 1 "$size" > "$tmp/in/appliance.img.manifest"; ! INSTALLER_ROOT="$tmp/in" TARGET_ROOT="$tmp/target" "$ROOT/installer/install.sh" --check-only ;;
  complete) mkdir -p "$tmp/target/var/lib/ashipaos"; printf installed > "$tmp/target/var/lib/ashipaos/install-complete"; ! INSTALLER_ROOT="$tmp/in" TARGET_ROOT="$tmp/target" "$ROOT/installer/install.sh" --check-only ;;
  force-invalid) mkdir -p "$tmp/target"; ! INSTALLER_ROOT="$tmp/in" TARGET_ROOT="$tmp/target" "$ROOT/installer/install.sh" --check-only ashipaos.force=1 ;;
  force-valid) mkdir -p "$tmp/target/var/lib/ashipaos"; printf installed > "$tmp/target/var/lib/ashipaos/install-complete"; INSTALLER_ROOT="$tmp/in" TARGET_ROOT="$tmp/target" "$ROOT/installer/install.sh" --check-only ashipaos.force=1 ;;
  *) exit 2 ;;
esac
