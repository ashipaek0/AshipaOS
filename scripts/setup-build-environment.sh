#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive
printf '%s\n' 'AshipaOS A95X build environment'
printf '%s\n' 'Full image construction is performed by GitHub Actions.'
printf '%s\n' 'Required local validation: Python 3, shellcheck, jq, sfdisk, and the pinned CoreELEC tooling.'
[[ -d "$ROOT_DIR/build/coreelec" ]] || { printf 'CoreELEC tooling is missing\n' >&2; exit 1; }
