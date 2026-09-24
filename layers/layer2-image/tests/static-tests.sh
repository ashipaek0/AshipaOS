#!/usr/bin/env bash
# Layer 2 STATIC: configuration validates and the builder can never write to a
# device, eMMC, or the U-Boot environment.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer2-image"
SCRIPT="$LAYER/scripts/build-image.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$SCRIPT"
bash "$SCRIPT" --validate >/dev/null 2>&1 || fail "image-config.yaml does not validate"
! grep -Eq 'of=/dev/|saveenv|mmc write|losetup|guestfish' "$SCRIPT" || fail "builder writes devices, eMMC or the U-Boot environment"
python3 - "$LAYER/files/a95x-f3-air" <<'PY'
import hashlib, json, pathlib, sys
d = pathlib.Path(sys.argv[1])
provenance = json.loads((d / "provenance.json").read_text(encoding="utf-8"))
for name, facts in provenance["stock_inputs"].items():
    if hashlib.sha256((d / name).read_bytes()).hexdigest() != facts["sha256"]:
        raise SystemExit(f"stock input {name} does not match its recorded SHA-256")
PY
printf '%s\n' 'A95X Layer 2 static contract: PASS'
