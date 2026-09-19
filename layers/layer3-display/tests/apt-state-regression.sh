#!/usr/bin/env bash
# Regression test for stale target-rootfs APT indexes.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer3-display/scripts/build-display.sh"

# The installer must discard debootstrap/mirror indexes before loading the
# immutable snapshot. Otherwise old lists can make snapshot packages appear
# unavailable or mix candidates from different repositories.
grep -q 'rm -rf -- "\$rootfs/var/lib/apt/lists/"\*' "$SCRIPT"
grep -q 'mkdir -p "\$rootfs/var/lib/apt/lists/partial"' "$SCRIPT"
grep -q 'dpkg --print-architecture' "$SCRIPT"
grep -q 'APT::Architecture=amd64' "$SCRIPT"
grep -q 'APT::Architectures=amd64' "$SCRIPT"
grep -q 'diagnose_apt_state' "$SCRIPT"
grep -q 'dpkg --print-foreign-architectures' "$SCRIPT"
grep -q 'apt-config "\${apt_options\[@\]}" dump' "$SCRIPT"
grep -q 'Acquire::(Check-Valid-Until|By-Hash)' "$SCRIPT"
grep -q 'apt-cache.*policy' "$SCRIPT"
grep -q 'policy=$(run_target "\$rootfs" apt-cache "\${apt_options\[@\]}" policy "\$pkg"' "$SCRIPT"
grep -q 'dpkg --get-selections' "$SCRIPT"
grep -q 'apt-mark showhold' "$SCRIPT"
grep -q 'installed resolver-relevant packages' "$SCRIPT"
grep -q 'Debug::pkgProblemResolver=yes' "$SCRIPT"
grep -q 'Debug::pkgDepCache::Marker=1' "$SCRIPT"
grep -q 'NR <= 240' "$SCRIPT"

# Credential diagnostics must redact values whether the separator is tight or
# followed by whitespace, without leaking the fixture secret to the output.
fixture=$'Password: supersecret\nToken= tokensecret\nAuthorization: bearersecret'
redacted=$(printf '%s\n' "$fixture" | sed -E \
    's#(https?://)[^/@[:space:]]+@#\1REDACTED@#g; s#([Pp]ass(word|wd)|[Tt]oken|[Ss]ecret|[Aa]uthorization)[=:][[:space:]]*[^[:space:]]+#\1=REDACTED#g')
[[ "$redacted" == $'Password=REDACTED\nToken=REDACTED\nAuthorization=REDACTED' ]]
! grep -qE 'supersecret|tokensecret|bearersecret' <<<"$redacted"
printf 'layer3-display-apt-state-regression: PASS\n'
