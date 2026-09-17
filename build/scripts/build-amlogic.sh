#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-0.0.1-dev}"
SOURCE="$ROOT/amlogic-coreelec-fork/source"
OUTPUT="$ROOT/build/output/amlogic"
BOX_CONFIG="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"

[[ "$(id -u)" -ne 0 ]] || {
  echo "CoreELEC does not support building as root; use an unprivileged build user" >&2
  exit 1
}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Version must be SemVer-compatible" >&2
  exit 2
}
AVAILABLE_KIB="$(df --output=avail "$ROOT" | tail -1 | tr -d ' ')"
(( AVAILABLE_KIB >= 80 * 1024 * 1024 )) || {
  echo "Amlogic builds require at least 80 GiB free (100 GiB recommended)" >&2
  exit 1
}

read_coreelec_value() {
  local key="$1"
  awk -v wanted="$key" '
    /^coreelec:$/ { section=1; next }
    section && /^[^[:space:]#]/ { exit }
    section && $1 == wanted ":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$BOX_CONFIG"
}
PROJECT="$(read_coreelec_value project)"
DEVICE="$(read_coreelec_value device)"
[[ "$PROJECT" == Amlogic-ce && "$DEVICE" == Amlogic-ng ]] || {
  echo "Unsupported or incomplete CoreELEC project/device selection" >&2
  exit 2
}

"$ROOT/build/scripts/prepare-coreelec.sh"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

env \
  PROJECT="$PROJECT" \
  ARCH=arm \
  DEVICE="$DEVICE" \
  BUILDER_NAME=AshipaOS \
  CUSTOM_VERSION="$VERSION" \
  CUSTOM_GIT_HASH="$SOURCE_COMMIT" \
  make -C "$SOURCE" image

mapfile -t IMAGES < <(find "$SOURCE/target" -maxdepth 1 -type f -name '*Generic*.img.gz' -print | LC_ALL=C sort)
[[ ${#IMAGES[@]} -gt 0 ]] || {
  echo "CoreELEC did not produce the required Generic Amlogic image" >&2
  exit 1
}
for image in "${IMAGES[@]}"; do
  cp "$image" "$OUTPUT/"
done

(cd "$OUTPUT" && sha256sum -- *.img.gz >SHA256SUMS)
python3 - "$OUTPUT/ashipaos-a95x-f3-air.manifest.json" "$VERSION" "$PROJECT" "$DEVICE" \
  "$SOURCE_COMMIT" "$(read_coreelec_value commit)" "$OUTPUT" <<'PYEOF'
import hashlib, json, pathlib, sys
output = pathlib.Path(sys.argv[7])
artifacts = []
for image in sorted(output.glob("*.img.gz")):
    artifacts.append({
        "name": image.name,
        "sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
    })
manifest = {
    "schema_version": 1,
    "version": sys.argv[2],
    "target": "a95x-f3-air",
    "track": "coreelec-baseline",
    "project": sys.argv[3],
    "device": sys.argv[4],
    "source_commit": sys.argv[5],
    "coreelec_commit": sys.argv[6],
    "artifacts": artifacts,
    "verification": {"build": "passed", "hardware": "blocked"},
}
pathlib.Path(sys.argv[1]).write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PYEOF
echo "Created Amlogic development baseline artifacts in $OUTPUT"
