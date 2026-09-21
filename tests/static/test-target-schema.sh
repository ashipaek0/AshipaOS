#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
grep -q 'a95x-f3-air' "$ROOT/schemas/target.schema.json"
grep -q 'arm64' "$ROOT/schemas/target.schema.json"
printf '%s\n' 'A95X target schema contract: PASS'
