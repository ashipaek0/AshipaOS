#!/usr/bin/env bash
# STATIC: this branch carries exactly one target and no other appliance track.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ "$(git ls-files build/targets)" == build/targets/amlogic/boxes/a95x-f3-air.yaml ]] || fail "only the a95x-f3-air target may exist"
[[ -d build/coreelec ]] || fail "CoreELEC provenance tooling is missing"
if git grep -nEi 'x86_64|raspberry|pi[45]\.yaml|build-x86|build-pi|/home/[a-z]' -- layers rootfs-overlay scripts .github ':!layers/*/tests/*'; then
  fail "foreign target or host-specific path found"
fi
printf '%s\n' 'A95X target isolation: PASS'
