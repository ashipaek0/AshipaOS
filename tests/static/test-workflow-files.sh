#!/usr/bin/env bash
# STATIC: workflows parse, pin every action to a full commit SHA, reference only
# repository files that exist, and keep the build A95X-only.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib, re, sys
import yaml

root = pathlib.Path(sys.argv[1])
errors = []
workflows = sorted((root / ".github/workflows").glob("*.yml"))
if not workflows:
    errors.append("no workflows found")
path_re = re.compile(r"(?<![\w./-])((?:layers|scripts|tests|build|schemas)/[\w./-]+\.(?:sh|py|json|yaml))")
for wf in workflows:
    text = wf.read_text(encoding="utf-8")
    doc = yaml.safe_load(text)
    for name, job in doc["jobs"].items():
        if "timeout-minutes" not in job:
            errors.append(f"{wf.name}: job {name} has no timeout-minutes")
        for step in job.get("steps", []):
            uses = step.get("uses")
            if uses and not re.fullmatch(r"[\w.-]+/[\w.-]+@[0-9a-f]{40}", uses):
                errors.append(f"{wf.name}: action not pinned to a commit SHA: {uses}")
            for ref in path_re.findall(step.get("run", "")):
                if not (root / ref).exists():
                    errors.append(f"{wf.name}: step '{step.get('name', uses)}' references missing {ref}")
build = yaml.safe_load((root / ".github/workflows/build-images.yml").read_text(encoding="utf-8"))
if set(build["jobs"]) != {"static-tests", "build-a95x-f3-air", "create-release"}:
    errors.append(f"build-images.yml jobs changed: {sorted(build['jobs'])}")
if errors:
    raise SystemExit("\n".join(errors))
PY
printf '%s\n' 'workflow contract: PASS'
