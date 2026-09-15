#!/usr/bin/env bash
# Layer 0 STATIC: GitHub workflow files must be well-formed YAML.
# Uses PyYAML if present; otherwise falls back to a minimal sanity check.
# Never fails for missing optional dependencies.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PYEOF'
import sys, os, glob

root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, ".github/workflows/*.yml")))
assert files, "no workflow files found"

try:
    import yaml  # type: ignore
    have_yaml = True
except ImportError:
    have_yaml = False

for p in files:
    with open(p) as f:
        text = f.read()
    assert text.strip(), "empty: %s" % p
    if have_yaml:
        d = yaml.safe_load(text)
        assert isinstance(d, dict), "not a mapping: %s" % p
        assert "jobs" in d, "missing jobs: %s" % p
        print("yaml-ok: %s" % os.path.relpath(p, root))
    else:
        assert "jobs:" in text, "missing jobs: %s" % p
        print("sanity-ok (pyyaml unavailable, SKIP parse): %s" % os.path.relpath(p, root))

print("test-workflow-files: PASS")
PYEOF
