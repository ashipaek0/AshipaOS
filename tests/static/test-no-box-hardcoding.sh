#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml" ]]
[[ -d "$ROOT/build/coreelec" ]]
printf '%s\n' 'A95X target isolation: PASS'
