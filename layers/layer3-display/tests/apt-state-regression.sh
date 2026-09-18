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
grep -q 'libswresample4 libavcodec59 libavdevice59 libavfilter8 libavformat59 mpv libmpv2' "$SCRIPT"
printf 'layer3-display-apt-state-regression: PASS\n'
