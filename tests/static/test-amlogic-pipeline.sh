#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOX="$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml"
PACKAGE="$ROOT/packages/ashipaos/coreelec/ashipaos-dev-baseline"

command -v rg >/dev/null 2>&1 || {
  echo "test-amlogic-pipeline requires ripgrep (rg)" >&2
  exit 1
}

grep -q '^  project: Amlogic-ce$' "$BOX"
grep -q '^  device: Amlogic-ng$' "$BOX"
grep -q '^  value: Amlogic-ng$' "$BOX"
grep -q '^PKG_NAME="ashipaos-dev-baseline"$' "$PACKAGE/package.mk"
grep -q '^WantedBy=multi-user.target$' "$PACKAGE/system.d/ashipaos-dev-baseline.service"

if rg -ni 'a95x|f3-air|device[_ -]?tree|\.dtb' "$PACKAGE"; then
  echo "Generic CoreELEC package contains box-specific data" >&2
  exit 1
fi
echo "test-amlogic-pipeline: PASS"
