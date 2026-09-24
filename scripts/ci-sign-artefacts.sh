#!/usr/bin/env bash
# CI: detached, ASCII-armoured GPG signatures (<file>.asc) for release artefacts.
# Usage: ci-sign-artefacts.sh <file-or-dir>...
#   Directories contribute their *.img.gz, *.pkg and SHA256SUMS-* files.
#
# Signing requires a secret key whose user ID contains "AshipaOS Release".
# Without one it fails closed. Development runs may opt in to placeholder
# files with CI_ALLOW_PLACEHOLDER_SIGNATURES=1; tag builds never can.
set -Eeuo pipefail

KEY_UID="AshipaOS Release"
PLACEHOLDER="PLACEHOLDER_SIGNATURE (development build; this is not a signature)"

[[ $# -ge 1 ]] || { printf 'Usage: %s <file-or-dir>...\n' "$(basename "$0")" >&2; exit 2; }

files=()
for arg in "$@"; do
    if [[ -d "$arg" ]]; then
        while IFS= read -r -d '' f; do files+=("$f"); done < <(
            find "$arg" -maxdepth 1 -type f \( -name '*.img.gz' -o -name '*.pkg' -o -name 'SHA256SUMS-*' \) \
                ! -name '*.asc' -print0 | sort -z)
    elif [[ -f "$arg" ]]; then
        files+=("$arg")
    else
        printf 'WARNING: nothing to sign at %s\n' "$arg" >&2
    fi
done
((${#files[@]} > 0)) || { echo "ERROR: no artefacts found to sign" >&2; exit 1; }

echo "=== Signing ${#files[@]} artefact(s) ==="
if ! gpg --batch --list-secret-keys "$KEY_UID" >/dev/null 2>&1; then
    if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
        echo "ERROR: release signing key not found for tag build; refusing placeholder signatures." >&2
        exit 1
    fi
    if [[ "${CI_ALLOW_PLACEHOLDER_SIGNATURES:-0}" != 1 ]]; then
        echo "ERROR: release signing key not found and placeholder signatures are not enabled." >&2
        echo "Set CI_ALLOW_PLACEHOLDER_SIGNATURES=1 only for explicit development validation." >&2
        exit 1
    fi
    echo "WARNING: no release key; writing development placeholders (NOT signatures)."
    for f in "${files[@]}"; do
        printf '%s\n' "$PLACEHOLDER" >"$f.asc"
        echo "  placeholder: $(basename "$f").asc"
    done
    exit 0
fi

for f in "${files[@]}"; do
    # The passphrase goes through a pipe, never argv or the environment of gpg.
    printf '%s' "${GPG_PASSPHRASE:-}" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
        --local-user "$KEY_UID" --armor --detach-sign --output "$f.asc" "$f"
    gpg --batch --verify "$f.asc" "$f" 2>/dev/null || { echo "ERROR: signature does not verify: $f" >&2; exit 1; }
    echo "  signed: $(basename "$f").asc"
done
echo "=== Signing complete ==="
