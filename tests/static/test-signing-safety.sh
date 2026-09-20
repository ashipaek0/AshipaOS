#!/usr/bin/env bash
# STATIC: signing must fail closed without a release key unless explicitly in dev mode.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIGNER="$ROOT/scripts/ci-sign-artefacts.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

bash -n "$SIGNER"

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/images" "$dir/ota" "$dir/output" "$dir/gnupg"
  chmod 700 "$dir/gnupg"
  printf 'image\n' > "$dir/images/test.img.gz"
  printf 'package\n' > "$dir/ota/test.pkg"
  printf '{"name":"fixture"}\n' > "$dir/output/sbom.json"
}

# A tag must fail and must not emit any placeholder signature.
TAG="$TMP/tag"
make_fixture "$TAG"
if GITHUB_WORKSPACE="$TAG" GITHUB_REF='refs/tags/v9.9.9' GNUPGHOME="$TAG/gnupg" \
    bash "$SIGNER" "$TAG/images" "$TAG/ota"; then
  printf 'FAIL: tag signing unexpectedly succeeded without a release key\n' >&2
  exit 1
fi
! find "$TAG" -type f \( -name '*.sig' -o -name '*.asc' \) -print -quit | grep -q .

# A non-tag run without the explicit opt-in must also fail closed.
NO_OPT="$TMP/no-opt"
make_fixture "$NO_OPT"
if GITHUB_WORKSPACE="$NO_OPT" GITHUB_REF='refs/heads/dev' GNUPGHOME="$NO_OPT/gnupg" \
    bash "$SIGNER" "$NO_OPT/images" "$NO_OPT/ota"; then
  printf 'FAIL: no-opt signing unexpectedly succeeded without a release key\n' >&2
  exit 1
fi

# Explicit development mode may create placeholders for images, OTA, and SBOM.
DEV="$TMP/dev"
make_fixture "$DEV"
CI_ALLOW_PLACEHOLDER_SIGNATURES=1 GITHUB_WORKSPACE="$DEV" GITHUB_REF='refs/heads/dev' \
  GNUPGHOME="$DEV/gnupg" bash "$SIGNER" "$DEV/images" "$DEV/ota"
for sig in "$DEV/images/test.img.gz.sig" "$DEV/ota/test.pkg.sig" "$DEV/output/sbom.json.sig"; do
  [[ -f "$sig" ]] || { printf 'FAIL: missing development signature %s\n' "$sig" >&2; exit 1; }
  grep -Fxq 'PLACEHOLDER_SIGNATURE' "$sig"
done
[[ -s "$DEV/output/sbom.json.sha256" ]]

printf 'test-signing-safety: PASS\n'
