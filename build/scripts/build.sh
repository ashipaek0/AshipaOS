#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="a95x-f3-air"
case "${1:-}" in
  --validate-coreelec) exec python3 "$ROOT_DIR/build/coreelec/validate-ce2a-manifest.py" ;;
  "" ) printf '%s\n' 'A95X build entry point: use GitHub Actions for full image construction.' ;;
  *) printf 'Only --validate-coreelec is available locally\n' >&2; exit 2 ;;
esac
