#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:-$ROOT/build/output/amlogic}"
MANIFEST="$OUTPUT/ashipaos-a95x-f3-air.manifest.json"

(cd "$OUTPUT" && sha256sum --check SHA256SUMS)
for image in "$OUTPUT"/*.img.gz; do gzip --test "$image"; done
python3 - "$MANIFEST" <<'PYEOF'
import json, pathlib, re, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["version"] == "0.0.1-dev"
assert manifest["target"] == "a95x-f3-air"
assert manifest["project"] == "Amlogic-ce"
assert manifest["device"] == "Amlogic-ng"
assert manifest["track"] == "coreelec-baseline"
assert manifest["verification"] == {"build": "passed", "hardware": "blocked"}
assert re.fullmatch(r"[0-9a-f]{40}", manifest["coreelec_commit"])
assert manifest["artifacts"]
assert any("Generic" in artifact["name"] for artifact in manifest["artifacts"])
PYEOF
echo "test-amlogic-image: PASS"
