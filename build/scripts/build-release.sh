#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-x86_64}"
VERSION="${2:-0.1.0-dev}"

[[ "$TARGET" == x86_64 ]] || { echo "Only x86_64 release builds are implemented" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Version must be SemVer-compatible" >&2
  exit 2
}
[[ "$(id -u)" -eq 0 ]] || { echo "Release builds require root privileges" >&2; exit 1; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]] || {
  echo "Release builds require a clean source tree" >&2
  exit 1
}
[[ ! -e "$ROOT/build/rootfs/$TARGET" && ! -e "$ROOT/build/output/ashipaos-$TARGET.img" ]] || {
  echo "Remove existing generated rootfs/output before starting a clean release build" >&2
  exit 1
}

for test_script in "$ROOT"/tests/static/*.sh; do
  bash "$test_script"
done
"$ROOT/build/scripts/bootstrap-rootfs.sh" "$TARGET"
"$ROOT/build/scripts/configure-rootfs.sh" "$TARGET"
"$ROOT/tests/build/test-rootfs.sh" "$TARGET"
ASHIPAOS_VERSION="$VERSION" "$ROOT/build/scripts/assemble-image.sh" "$TARGET"
"$ROOT/tests/build/test-image.sh" "$TARGET"
if [[ "${ASHIPAOS_SKIP_VM:-0}" != 1 ]]; then
  "$ROOT/tests/vm/test-boot.sh" "$ROOT/build/output/ashipaos-$TARGET.img"
fi
python3 - "$ROOT/build/output/ashipaos-$TARGET.manifest.json" "${ASHIPAOS_SKIP_VM:-0}" <<'PYEOF'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["verification"]["build"] = "passed"
manifest["verification"]["vm"] = "pending-ci" if sys.argv[2] == "1" else "passed"
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PYEOF

echo "Development release build complete: $VERSION ($TARGET)"
