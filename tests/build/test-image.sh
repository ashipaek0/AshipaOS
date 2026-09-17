#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-x86_64}"
OUTPUT="${2:-$ROOT/build/output}"
IMAGE="$OUTPUT/ashipaos-$TARGET.img"
MANIFEST="$OUTPUT/ashipaos-$TARGET.manifest.json"
LOOP_DEVICE=""

cleanup() {
  set +e
  [[ -z "$LOOP_DEVICE" ]] || losetup --detach "$LOOP_DEVICE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

zstd --test "$IMAGE.zst"
(cd "$OUTPUT" && sha256sum --check "$(basename "$IMAGE.zst").sha256")
python3 - "$MANIFEST" "$IMAGE.zst" "$OUTPUT" <<'PYEOF'
import hashlib, json, pathlib, re, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest["schema_version"] == 1
assert manifest["target"] == "x86_64"
assert manifest["verification"]["hardware"] == "blocked"
assert re.fullmatch(r"[0-9a-f]{40}", manifest["source_commit"])
digest = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
assert digest == manifest["sha256"]
lock = pathlib.Path(sys.argv[3]) / manifest["packages_lock"]["file"]
assert lock.name == "ashipaos-x86_64.packages.lock"
assert lock.is_file() and lock.stat().st_size > 0
assert hashlib.sha256(lock.read_bytes()).hexdigest() == manifest["packages_lock"]["sha256"]
PYEOF

[[ "$(parted --machine --script "$IMAGE" print | sed -n '2p' | cut -d: -f6)" == gpt ]] || {
  echo "Image does not use GPT" >&2; exit 1;
}
LOOP_DEVICE="$(losetup --find --show --partscan "$IMAGE")"
udevadm settle
[[ "$(blkid -s LABEL -o value "${LOOP_DEVICE}p2")" == ashipaos-root ]]
[[ "$(blkid -s LABEL -o value "${LOOP_DEVICE}p3")" == ashipaos-storage ]]
echo "test-image: PASS"
