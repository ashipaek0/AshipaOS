#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGETS_DIR="$ROOT_DIR/build/targets"
printf 'AshipaOS x86_64 target\n'
[[ -f "$TARGETS_DIR/x86_64.yaml" ]] || { echo 'missing x86_64 target' >&2; exit 1; }
cat "$TARGETS_DIR/x86_64.yaml"
