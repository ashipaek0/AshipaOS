#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"
CHECKOUT_SCRIPT="$ROOT/build/scripts/checkout-coreelec.sh"

python3 - "$CONFIG" <<'PYEOF'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"(?ms)^coreelec:\n((?:^[ ]+.*\n?)+)", text)
assert match, "missing coreelec pin"
block = match.group(1)

values = {}
for line in block.splitlines():
    item = re.match(r"^  (repository|ref|commit|project|device):\s*(\S+)\s*$", line)
    if item:
        values[item.group(1)] = item.group(2)

assert set(values) == {"repository", "ref", "commit", "project", "device"}, "incomplete coreelec pin"
assert values["repository"].startswith("https://"), "repository must use HTTPS"
assert re.fullmatch(r"[0-9a-f]{40}", values["commit"]), "commit must be a full SHA"
assert values["ref"] not in {"main", "master", "nightly"}, "development branch is not a stable pin"
assert values["project"] == "Amlogic-ce"
assert values["device"] == "Amlogic-ng"
print(f"CoreELEC pin: {values['ref']} ({values['commit']})")
PYEOF

[[ -x "$CHECKOUT_SCRIPT" ]] || {
  echo "checkout script is not executable: $CHECKOUT_SCRIPT" >&2
  exit 1
}

echo "test-coreelec-pin: PASS"
