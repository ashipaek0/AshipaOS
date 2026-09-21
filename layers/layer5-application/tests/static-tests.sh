#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer5-application"
SCRIPT="$LAYER/scripts/build-application.sh"
LAUNCHER="$LAYER/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
CONFIG="$LAYER/config/application-config.yaml"
LOCK="$LAYER/config/dependencies.lock.json"
[[ -x "$SCRIPT" && -x "$LAUNCHER" ]]
[[ -f "$CONFIG" && -f "$LOCK" ]]
grep -q '^#!/usr/bin/env bash$' "$SCRIPT" "$LAUNCHER"
grep -q 'RESOLVED' "$SCRIPT" "$LAUNCHER"
grep -q 'manylinux_2_27_aarch64' "$LAYER/scripts/resolve-dependencies-arm64.py"
grep -q 'qemu-aarch64-static' "$LAYER/scripts/resolve-dependencies-arm64.py"
grep -q 'python3' "$SCRIPT"
grep -q 'zipfile' "$SCRIPT"
grep -q 'resolution, tmp, rootfs, archive, target_name = map' "$SCRIPT"
grep -q 'rootfs_output_owner' "$SCRIPT"
grep -q 'a95x-f3-air' "$SCRIPT" "$CONFIG"
grep -q 'dependency_status.*RESOLVED' "$LAUNCHER"
grep -q 'any(platform in value\["platform_tag"\]' "$LAUNCHER"
grep -q 'python-mpv>=1.0.8' "$CONFIG" "$LOCK"
grep -q 'jellyfin-apiclient-python>=1.18.0' "$CONFIG" "$LOCK"
grep -q 'python-mpv-jsonipc>=1.4.0' "$CONFIG" "$LOCK"
! grep -q 'python3-mpv' "$CONFIG" "$SCRIPT"
printf 'layer5-application-static: PASS\n'
