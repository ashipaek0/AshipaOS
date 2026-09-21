#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer5-application"
grep -q 'x86_64' "$LAYER/config/application-config.yaml" "$LAYER/scripts/build-application.sh"
grep -q 'manylinux_2_17_x86_64' "$LAYER/scripts/resolve-dependencies.py"
printf '%s\n' 'x86_64 application contract: PASS'
