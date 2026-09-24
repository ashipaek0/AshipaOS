#!/usr/bin/env bash
set -Eeuo pipefail
key=${1-}
[[ "$key" != *$'\n'* && "$key" != *$'\r'* ]] || exit 1
[[ "$key" =~ ^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp[0-9]+)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || exit 1
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$key" > "$tmp"
ssh-keygen -lf "$tmp" >/dev/null 2>&1
