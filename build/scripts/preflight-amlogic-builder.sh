#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_FILE="$ROOT/build/config/coreelec-host-packages.txt"
MINIMUM_MEMORY_KIB=$((16 * 1024 * 1024))
# A runner is provisioned with 100 GiB free. The build starts only while at
# least 80 GiB remains in the checked-out workspace after runner/tool overhead.
MINIMUM_WORKSPACE_KIB=$((80 * 1024 * 1024))

if (( EUID == 0 )); then
  echo "CoreELEC does not support building as root; use an unprivileged runner account" >&2
  exit 1
fi

memory_kib="$(awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo)"
if [[ ! "$memory_kib" =~ ^[0-9]+$ ]] || (( memory_kib < MINIMUM_MEMORY_KIB )); then
  echo "Amlogic builders require at least 16 GiB RAM" >&2
  exit 1
fi

workspace_kib="$(df --output=avail "$ROOT" | awk 'NR == 2 { print $1 }')"
if [[ ! "$workspace_kib" =~ ^[0-9]+$ ]] || (( workspace_kib < MINIMUM_WORKSPACE_KIB )); then
  echo "Amlogic builders require 100 GiB free when provisioned and at least 80 GiB available in the workspace at build time" >&2
  exit 1
fi

mapfile -t required_packages < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$PACKAGE_FILE")
if (( ${#required_packages[@]} == 0 )); then
  echo "CoreELEC host package declaration is empty: $PACKAGE_FILE" >&2
  exit 1
fi

missing_packages=()
for package in "${required_packages[@]}"; do
  if ! dpkg-query --show --showformat='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx installed; then
    missing_packages+=("$package")
  fi
done

if (( ${#missing_packages[@]} > 0 )); then
  printf 'Missing declared CoreELEC host package: %s\n' "${missing_packages[@]}" >&2
  exit 1
fi

echo "Amlogic builder preflight passed"
