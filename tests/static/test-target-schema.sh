#!/usr/bin/env bash
# Layer 0 STATIC: target/box YAML stubs must satisfy their JSON schemas.
# Uses `jsonschema` if installed; else a stdlib structural check with
# PyYAML if present; else verifies schemas parse and stubs exist (SKIP).
# CI requires both dependencies so canonical validation cannot silently degrade.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PYEOF'
import json, sys, os

root = sys.argv[1]
ok = True

def load_json(p):
    with open(p) as f:
        return json.load(f)

try:
    target_schema = load_json(os.path.join(root, "schemas/target.schema.json"))
    box_schema = load_json(os.path.join(root, "schemas/box.schema.json"))
except Exception as e:
    print("schema JSON parse failed: %s" % e)
    sys.exit(1)

try:
    import yaml  # type: ignore
    have_yaml = True
except ImportError:
    have_yaml = False

try:
    import jsonschema  # type: ignore
    have_jsonschema = True
except ImportError:
    have_jsonschema = False

if os.environ.get("CI") and not (have_yaml and have_jsonschema):
    print("CI requires PyYAML and jsonschema for target validation", file=sys.stderr)
    sys.exit(1)

targets = [
    os.path.join(root, "build/targets/pi4.yaml"),
    os.path.join(root, "build/targets/pi5.yaml"),
    os.path.join(root, "build/targets/x86_64.yaml"),
]
boxes = [os.path.join(root, "build/targets/amlogic/boxes/a95x-f3-air.yaml")]

if have_yaml and have_jsonschema:
    for p in targets:
        with open(p) as f:
            jsonschema.validate(yaml.safe_load(f), target_schema)
        print("valid: %s" % os.path.relpath(p, root))
    for p in boxes:
        with open(p) as f:
            jsonschema.validate(yaml.safe_load(f), box_schema)
        print("valid: %s" % os.path.relpath(p, root))
elif have_yaml:
    for p in targets:
        with open(p) as f:
            d = yaml.safe_load(f)
        assert isinstance(d, dict) and all(k in d for k in ("name", "arch", "status")), p
        print("structural-ok: %s" % os.path.relpath(p, root))
    for p in boxes:
        with open(p) as f:
            d = yaml.safe_load(f)
        assert isinstance(d, dict) and all(k in d for k in ("name", "status", "soc", "kernel_branch", "coreelec")), p
        print("structural-ok: %s" % os.path.relpath(p, root))
else:
    for p in targets + boxes:
        assert os.path.isfile(p) and os.path.getsize(p) > 0, p
        print("present (yaml/jsonschema unavailable, SKIP deep check): %s" % os.path.relpath(p, root))

print("test-target-schema: PASS")
PYEOF
