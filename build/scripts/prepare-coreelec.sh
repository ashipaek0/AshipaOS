#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT/amlogic-coreelec-fork/source"
PACKAGE_SOURCE="$ROOT/packages/ashipaos/coreelec/ashipaos-dev-baseline"
PACKAGE_DESTINATION="$SOURCE/packages/ashipaos/ashipaos-dev-baseline"
CORE_OPTIONS="$SOURCE/distributions/CoreELEC/options"

# The integration directory is generated and untracked inside the pinned tree.
# Remove only that owned path so an interrupted previous run is recoverable.
rm -rf "$PACKAGE_DESTINATION"
if [[ -d "$SOURCE/.git" ]]; then
  git -C "$SOURCE" restore -- distributions/CoreELEC/options
fi
"$ROOT/build/scripts/checkout-coreelec.sh" "$SOURCE"
[[ -f "$PACKAGE_SOURCE/package.mk" ]] || {
  echo "AshipaOS CoreELEC package is missing" >&2
  exit 1
}

mkdir -p "$(dirname "$PACKAGE_DESTINATION")"
rm -rf "$PACKAGE_DESTINATION"
cp -a "$PACKAGE_SOURCE" "$PACKAGE_DESTINATION"
cat >>"$CORE_OPTIONS" <<'EOF'

# AshipaOS source-controlled development integration.
ADDITIONAL_PACKAGES+=" ashipaos-dev-baseline"
EOF

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
printf '%s\n' "$SOURCE_COMMIT" >"$PACKAGE_DESTINATION/ashipaos-source-commit"
echo "Prepared CoreELEC with AshipaOS integration from $SOURCE_COMMIT"
