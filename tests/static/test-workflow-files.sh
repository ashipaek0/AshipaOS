#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$ROOT/.github/workflows/build-images.yml"
grep -q '^  build-x86_64:' "$workflow"
grep -q 'needs: build-x86_64' "$workflow"
printf '%s\n' 'x86_64 workflow contract: PASS'
