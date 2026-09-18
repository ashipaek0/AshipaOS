#!/usr/bin/env bash
# Static and safe contract checks for the x86_64 Layer 3 display stack.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer3-display"
SCRIPT="$LAYER/scripts/build-display.sh"
LOCK="$LAYER/config/packages.lock"
SERVICE="$LAYER/files/etc/systemd/system/ashipaos-display.service"
SESSION="$LAYER/files/usr/libexec/ashipaos-display"
CONFIG="$LAYER/config/display-config.yaml"

[[ -x "$SCRIPT" ]]
[[ -x "$SESSION" ]]
[[ -f "$SERVICE" && -f "$CONFIG" && -f "$LOCK" ]]
grep -q '^set -Eeuo pipefail$' "$SCRIPT"
grep -q 'target.*x86_64' "$SCRIPT"
grep -q 'lock_source_line' "$SCRIPT"
grep -q 'Dir::Etc::sourcelist' "$SCRIPT"
grep -q 'snapshot.debian.org' "$LOCK"
grep -q 'apt-get.*update' "$SCRIPT"
grep -q 'apt-get.*--download-only.*install' "$SCRIPT"
grep -q 'sha256sum' "$SCRIPT"
grep -q 'dpkg-query' "$SCRIPT"
grep -q 'build-evidence.json' "$SCRIPT"
grep -q '^TEMP_DIR=""$' "$SCRIPT"
grep -q 'trap .cleanup;.*TEMP_DIR:-.*rm -rf --' "$SCRIPT"
! grep -q 'local input=.* temp output' "$SCRIPT"
grep -q 'command -v cage' "$SCRIPT"
grep -q 'command -v mpv' "$SCRIPT"
grep -q 'python3 -c.*import mpv.*mpv.MPV' "$SCRIPT"
grep -q 'ashipa' "$SERVICE"
grep -q 'XDG_RUNTIME_DIR=/run/user/%U' "$SERVICE"
grep -q 'Restart=on-failure' "$SERVICE"
grep -q 'SupplementaryGroups=video render seat' "$SERVICE"
grep -q 'cage' "$SESSION"
grep -q 'mpv' "$SESSION"
grep -q 'BLOCKED' "$SESSION"
! grep -qE 'curl|wget|base64|/usr/bin/(ffmpeg|yt-dlp)' "$SESSION"
! grep -qE '^(User|Group)=ashipaos$' "$SERVICE"
bash "$LAYER/tests/apt-state-regression.sh"
python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
assert lock["source"]["uri"].startswith("https://snapshot.debian.org/archive/debian/")
assert lock["source"]["suite"] == "bookworm"
assert set(lock["packages"]) == {"libdrm2", "libegl1", "libgl1-mesa-dri", "libgles2", "mesa-vulkan-drivers", "libwayland-client0", "libwayland-server0", "wayland-protocols", "cage", "seatd", "mpv", "python3-mpv"}
for name, item in lock["packages"].items():
    assert item["version"] and item["architecture"] in {"amd64", "all"}
    assert len(item["sha256"]) == 64
PY
printf 'layer3-display-static: PASS\n'
