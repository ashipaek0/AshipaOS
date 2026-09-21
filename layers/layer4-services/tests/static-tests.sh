#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer4-services/scripts/build-services.sh"
grep -q 'graphical.target' "$SCRIPT"
printf '%s\n' 'x86_64 services contract: PASS'
