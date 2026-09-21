#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="a95x-f3-air"
usage(){ printf 'Usage: %s [--validate-coreelec]\n' "$(basename "$0")"; }
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --validate-coreelec) exec python3 "$ROOT_DIR/build/coreelec/validate-ce2a-manifest.py" ;;
  "") ;;
  *) usage >&2; exit 2 ;;
esac
printf '%s\n' "A95X F3 Air orchestration contract: $TARGET"
printf '%s\n' 'Use the GitHub Actions build workflow for full image construction.'
