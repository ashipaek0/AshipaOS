#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT/build/targets/x86_64.yaml"
[[ -f "$TARGET" ]]
grep -q '^name: x86_64$' "$TARGET"
grep -q '^arch: x86_64$' "$TARGET"
printf '%s\n' 'x86_64 target schema contract: PASS'
