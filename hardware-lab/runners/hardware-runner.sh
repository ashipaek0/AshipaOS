#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-a95x-f3-air}"
[[ "$TARGET" == a95x-f3-air ]] || { printf 'Only a95x-f3-air is supported\n' >&2; exit 2; }
printf '%s\n' 'Hardware runner contract: removable SD and 3.3V TTL UART only'
