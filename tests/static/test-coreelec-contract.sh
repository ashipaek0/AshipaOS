#!/usr/bin/env bash
# Layer 0 STATIC: the A95X CoreELEC contract and confirmed DTB stay aligned.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"
CONTRACT="$ROOT/contracts/coreelec-integration.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

[[ -f "$CONTRACT" ]] || fail "CoreELEC integration contract exists"
python3 - "$TARGET" <<'PYEOF'
import copy
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
with path.open(encoding="utf-8") as stream:
    target = yaml.safe_load(stream)

expected = {
    "value": "sm1_s905x3_4g.dtb",
    "install_as": "dtb.img",
    "status": "CONFIRMED",
}


def device_tree_matches(document):
    device_tree = document.get("device_tree") if isinstance(document, dict) else None
    return isinstance(device_tree, dict) and all(
        device_tree.get(field) == value for field, value in expected.items()
    )


assert device_tree_matches(target), "target device_tree mapping does not match contract"

# Keep this regression test honest: each relevant mutation must be rejected,
# rather than accidentally matching a same-shaped field elsewhere in the YAML.
for field, value in (
    ("value", "wrong.dtb"),
    ("install_as", "wrong.img"),
    ("status", "UNKNOWN"),
):
    mutated = copy.deepcopy(target)
    mutated["device_tree"][field] = value
    assert not device_tree_matches(mutated), f"device_tree {field} mutation was accepted"
PYEOF
grep -q '^  wifi: UNKNOWN$' "$TARGET" || fail "target preserves Wi-Fi unknown status"
grep -q '^    final_bridge: UNKNOWN$' "$TARGET" || fail "target preserves final bridge unknown"
grep -q 'fc61125e8900ab0c2593a29b615980ed0cd5b939' "$CONTRACT" || fail "contract records CoreELEC commit"
grep -q 'c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a' "$CONTRACT" || fail "contract records CoreELEC archive hash"
grep -q 'sm1_s905x3_4g.dtb' "$CONTRACT" || fail "contract records exact DTB"
grep -q 'No final bridge, compositor, launcher, `hwdec` value' "$CONTRACT" || fail "contract preserves runtime unknowns"
grep -q 'Kodi must be excluded before image construction' "$CONTRACT" || fail "contract defines no-Kodi boundary"
grep -q 'Package graph closure' "$CONTRACT" || fail "contract defines package closure"
grep -q 'Persistence and service boundaries' "$CONTRACT" || fail "contract defines persistence/service boundaries"
grep -q 'Evidence classes and gates' "$CONTRACT" || fail "contract defines evidence classes"

pass "CoreELEC integration contract and DTB metadata"
