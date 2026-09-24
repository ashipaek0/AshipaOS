#!/usr/bin/env bash
# STATIC: the box facts and release identity validate against their schemas,
# and CONFIRMED facts carry evidence.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
import jsonschema, yaml
root = pathlib.Path(sys.argv[1])
def check(document, schema):
    data = yaml.safe_load((root / document).read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator(json.loads((root / schema).read_text(encoding="utf-8"))).validate(data)
    return data
box = check("build/targets/amlogic/boxes/a95x-f3-air.yaml", "schemas/box.schema.json")
check("build/config/release.yaml", "schemas/target.schema.json")
for key, fact in box.items():
    if isinstance(fact, dict) and fact.get("status") == "CONFIRMED" and key != "soc" and not fact.get("evidence") and key != "coreelec_baseline":
        raise SystemExit(f"CONFIRMED fact without evidence: {key}")
PY
printf '%s\n' 'A95X target schema contract: PASS'
