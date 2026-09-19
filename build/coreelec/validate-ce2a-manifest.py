#!/usr/bin/env python3
"""Validate generated CE-2A evidence against the schema and immutable pin."""
import json
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("usage: validate-ce2a-manifest.py MANIFEST SCHEMA PIN")
manifest_path, schema_path, pin_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
schema = json.loads(schema_path.read_text(encoding="utf-8"))
pin = json.loads(pin_path.read_text(encoding="utf-8"))

try:
    import jsonschema
except ImportError as exc:
    raise SystemExit("jsonschema is required for CE-2A manifest validation") from exc

jsonschema.Draft202012Validator(schema).validate(manifest)
source = manifest["source"]
builder = manifest["builder"]
expected = {
    "source": {
        "repository": pin["source"]["repository"],
        "fork": pin["source"]["fork"],
        "tag": pin["source"]["ref"]["value"],
        "commit": pin["source"]["commit"],
        "archive_sha256": pin["source"]["archive"]["sha256"],
    },
    "builder": {
        "dockerfile": pin["builder"]["dockerfile"]["path"],
        "dockerfile_sha256": pin["builder"]["dockerfile"]["sha256"],
        "base_image": pin["builder"]["base_image"]["pinned_reference"],
        "base_digest": pin["builder"]["base_image"]["digest"],
        "amd64_manifest_digest": pin["builder"]["base_image"]["linux_amd64_manifest_digest"],
    },
    "tuple": pin["build"],
    "artifact_path": pin["artifact"]["path"],
}
if source != {**expected["source"], **{k: source[k] for k in source if k not in expected["source"]}}:
    # Compare the bound fields explicitly; extra evidence metadata is allowed.
    for key, value in expected["source"].items():
        if source.get(key) != value:
            raise SystemExit(f"manifest source pin mismatch: {key}")
for key, value in expected["builder"].items():
    if builder.get(key) != value:
        raise SystemExit(f"manifest builder pin mismatch: {key}")
if manifest["tuple"] != expected["tuple"]:
    raise SystemExit("manifest build tuple mismatch")
if manifest["artifact"].get("path") != expected["artifact_path"]:
    raise SystemExit("manifest artifact path mismatch")
dtb = manifest["dtb"]
if dtb["sha256"] != dtb["expected_sha256"]:
    raise SystemExit("manifest DTB hash is not bound to the inspected input")
print(f"valid CE-2A manifest: {manifest_path}")
