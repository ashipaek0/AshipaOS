#!/usr/bin/env bash
# Validate every locked package against its immutable Debian snapshot index.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
python3 - "$ROOT/layers/layer3-display/config/packages.lock" <<'PY'
import json, lzma, sys, urllib.request
lock = json.load(open(sys.argv[1], encoding="utf-8"))
base = lock["source"]["uri"].rstrip("/") + "/dists/" + lock["source"]["suite"] + "/main/binary-{} /Packages.xz"
base = base.replace("{} ", "{}")
records = {}
for arch in ("amd64", "all"):
    url = base.format(arch)
    with urllib.request.urlopen(url, timeout=60) as response:
        text = lzma.decompress(response.read()).decode("utf-8")
    for paragraph in text.split("\n\n"):
        fields = dict(line.split(": ", 1) for line in paragraph.splitlines() if ": " in line)
        if fields.get("Package"):
            records[(fields["Package"], fields.get("Architecture"))] = fields
for name, item in lock["packages"].items():
    record = records.get((name, item["architecture"]))
    if not record:
        raise SystemExit(f"missing locked package {name} {item['architecture']}")
    for field in ("Version", "Filename", "SHA256"):
        expected = item["version"] if field == "Version" else item[field.lower()]
        if field == "Filename":
            actual = record.get(field, "").rsplit("/", 1)[-1]
        else:
            actual = record.get(field)
        if actual != expected:
            raise SystemExit(f"lock mismatch for {name}: {field} {actual!r} != {expected!r}")
print("layer3-display-debian-packages: PASS (immutable Bookworm snapshot lock)")
PY
