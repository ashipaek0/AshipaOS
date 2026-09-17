#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PREFLIGHT="$ROOT/build/scripts/preflight-amlogic-builder.sh"
DOC="$ROOT/docs/amlogic-builder.md"

grep -Fq 'runs-on: [self-hosted, linux, x64, ashipaos-builder]' "$WORKFLOW"
grep -Fq 'build/scripts/preflight-amlogic-builder.sh' "$WORKFLOW"
grep -Fq 'build/config/coreelec-host-packages.txt' "$WORKFLOW"
grep -Fq 'MINIMUM_MEMORY_KIB=$((16 * 1024 * 1024))' "$PREFLIGHT"
grep -Fq 'MINIMUM_WORKSPACE_KIB=$((80 * 1024 * 1024))' "$PREFLIGHT"
grep -Fq 'self-hosted, linux, x64, ashipaos-builder' "$DOC"
grep -Fq '16 GiB RAM and 100 GiB free disk' "$DOC"
grep -Fq '80 GiB available-workspace floor' "$DOC"
grep -Fq '`build/config/coreelec-host-packages.txt`' "$DOC"
