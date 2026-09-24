#!/usr/bin/env bash
# STATIC: signing fails closed without a release key, placeholders need an
# explicit non-tag opt-in, and a real key yields verifiable signatures.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIGNER="$ROOT/scripts/ci-sign-artefacts.sh"
TMP="$(mktemp -d)"
trap 'gpgconf --homedir "$TMP/real/gnupg" --kill all >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$SIGNER"

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/images" "$dir/gnupg"
  chmod 700 "$dir/gnupg"
  printf 'image\n' >"$dir/images/test.img.gz"
  printf 'sums\n' >"$dir/images/SHA256SUMS-a95x-f3-air"
  printf '{"name":"fixture"}\n' >"$dir/sbom.json"
}
sign() { local dir="$1"; shift; env GNUPGHOME="$dir/gnupg" "$@" bash "$SIGNER" "$dir/images" "$dir/sbom.json"; }
no_signatures() { ! find "$1" -name '*.asc' -print -quit | grep -q .; }

# A tag must fail and must not emit anything, even with the opt-in set.
make_fixture "$TMP/tag"
if sign "$TMP/tag" GITHUB_REF=refs/tags/v9.9.9 CI_ALLOW_PLACEHOLDER_SIGNATURES=1 >/dev/null 2>&1; then
  fail "tag signing succeeded without a release key"
fi
no_signatures "$TMP/tag" || fail "tag run emitted signatures"

# A branch run without the explicit opt-in must also fail closed.
make_fixture "$TMP/no-opt"
if sign "$TMP/no-opt" GITHUB_REF=refs/heads/dev >/dev/null 2>&1; then
  fail "signing succeeded without a key or opt-in"
fi
no_signatures "$TMP/no-opt" || fail "no-opt run emitted signatures"

# Explicit development mode writes clearly-marked placeholders for every artefact.
make_fixture "$TMP/dev"
sign "$TMP/dev" GITHUB_REF=refs/heads/dev CI_ALLOW_PLACEHOLDER_SIGNATURES=1 >/dev/null
for f in images/test.img.gz images/SHA256SUMS-a95x-f3-air sbom.json; do
  grep -q '^PLACEHOLDER_SIGNATURE' "$TMP/dev/$f.asc" || fail "missing placeholder for $f"
done

# A real (throwaway, unprotected) release key produces verifiable signatures.
make_fixture "$TMP/real"
GNUPGHOME="$TMP/real/gnupg" gpg --batch --quiet --passphrase '' \
  --quick-gen-key 'AshipaOS Release (test) <release@invalid>' ed25519 sign 1d 2>/dev/null
sign "$TMP/real" GITHUB_REF=refs/tags/v9.9.9 >/dev/null
for f in images/test.img.gz images/SHA256SUMS-a95x-f3-air sbom.json; do
  GNUPGHOME="$TMP/real/gnupg" gpg --batch --verify "$TMP/real/$f.asc" "$TMP/real/$f" 2>/dev/null \
    || fail "signature for $f does not verify"
done

printf 'test-signing-safety: PASS\n'
