#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
"$SCRIPT" --layout-only "$TMP_DIR/x86-layout.img"
sfdisk --verify "$TMP_DIR/x86-layout.img" >/dev/null
python3 - "$TMP_DIR/x86-layout.img" <<'PY'
import json, subprocess, sys
layout=json.loads(subprocess.check_output(['sfdisk','--json',sys.argv[1]]))['partitiontable']
assert layout['label']=='gpt'
assert len(layout['partitions'])==2
assert layout['partitions'][0]['type'].lower().startswith('c12a7328')
print('x86_64 GPT layout: PASS')
PY
