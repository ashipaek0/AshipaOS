#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAUNCHER="$ROOT/layers/layer5-application/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
grep -q 'IMMUTABLE=' "$LAUNCHER"
grep -q 'dependency_status' "$LAUNCHER"
printf '%s\n' 'x86_64 application mutation contract: PASS'
