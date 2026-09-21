#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$ROOT/.github/workflows/build-images.yml"
grep -q '^  build-a95x-f3-air:' "$workflow"
! grep -q 'build-x86' "$workflow"
grep -q 'build-a95x-f3-air' "$workflow"
printf '%s\n' 'A95X workflow contract: PASS'
