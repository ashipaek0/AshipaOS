#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$ROOT/.github/workflows/build-images.yml"
job="$(awk '/^  build-x86_64:/{p=1} /^  create-release:/{p=0} p' "$workflow")"
grep -q 'layers/layer1-rootfs/scripts/build-rootfs.sh' <<<"$job"
grep -q 'layers/layer2-image/scripts/build-image.sh' <<<"$job"
grep -q 'tests/vm/boot-x86_64.sh' <<<"$job"
printf '%s\n' 'x86_64 pipeline contract: PASS'
