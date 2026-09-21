#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for dir in "$ROOT/build/targets" "$ROOT/layers" "$ROOT/tests"; do [[ -d "$dir" ]]; done
[[ -f "$ROOT/build/targets/x86_64.yaml" ]]
printf '%s\n' 'x86_64 target isolation: PASS'
