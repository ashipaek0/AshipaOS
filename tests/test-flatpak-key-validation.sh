#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export GNUPGHOME="$tmp/gnupg"
mkdir -m 0700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key 'Pinned fixture key' ed25519 sign 0 >/dev/null 2>&1
gpg --batch --passphrase '' --quick-generate-key 'Injected fixture key' ed25519 sign 0 >/dev/null 2>&1
mapfile -t fingerprints < <(gpg --batch --with-colons --list-keys | awk -F: '$1 == "pub" { need=1; next } need && $1 == "fpr" { print toupper($10); need=0 }')
[[ ${#fingerprints[@]} == 2 ]]
gpg --batch --export "${fingerprints[0]}" > "$tmp/one-primary.gpg"
gpg --batch --export "${fingerprints[@]}" > "$tmp/two-primaries.gpg"
"$root/scripts/validate-flatpak-key.sh" "$tmp/one-primary.gpg" "${fingerprints[0]}" 'Pinned fixture key'
if "$root/scripts/validate-flatpak-key.sh" "$tmp/two-primaries.gpg" "${fingerprints[0]}"; then
  echo 'keyring containing an injected second real primary key was accepted' >&2
  exit 1
fi
printf '%s\n' 'real GPG keyring single-primary validation: PASS'
