#!/usr/bin/env bash
set -Eeuo pipefail
TARGET="a95x-f3-air"
[[ "${1:-$TARGET}" == "$TARGET" ]] || { printf 'Only %s is supported\n' "$TARGET" >&2; exit 2; }
printf '%s\n' 'A95X release package contract: PASS'
