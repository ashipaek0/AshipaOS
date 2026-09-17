#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v rg >/dev/null 2>&1 || {
  echo "test-release-contract requires ripgrep (rg)" >&2
  exit 1
}

python3 -m json.tool "$ROOT/schemas/release-manifest.schema.json" >/dev/null
python3 -m json.tool "$ROOT/schemas/amlogic-release-manifest.schema.json" >/dev/null

if rg -n 'cp[[:space:]]+/boot/(vmlinuz|initrd)' "$ROOT/build" "$ROOT/rootfs-overlay"; then
  echo "Build code must not copy boot artefacts from the host" >&2
  exit 1
fi
grep -q 'trap cleanup EXIT INT TERM' "$ROOT/build/scripts/assemble-image.sh"
grep -q 'hardware.*blocked' "$ROOT/build/scripts/assemble-image.sh"
echo "test-release-contract: PASS"
