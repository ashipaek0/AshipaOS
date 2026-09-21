#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device="${1:-x86_64-generic}"
[[ "$device" == x86_64-generic ]] || { echo 'only x86_64-generic is supported on this branch' >&2; exit 2; }
mkdir -p "$ROOT_DIR/evidence/x86_64"
printf 'hardware runner target: %s\n' "$device"
