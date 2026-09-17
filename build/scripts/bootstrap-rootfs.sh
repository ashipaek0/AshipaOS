#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${1:-}"
DESTINATION="${2:-}"
TEMP_DIR=""

usage() {
  echo "Usage: $0 <target> [destination]" >&2
}

cleanup() {
  set +e
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

[[ -n "$TARGET" ]] || { usage; exit 2; }
[[ "$TARGET" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo "Invalid target name: $TARGET" >&2
  exit 2
}

CONFIG="$ROOT/build/targets/$TARGET.yaml"
[[ -f "$CONFIG" ]] || {
  echo "Unknown target: $TARGET" >&2
  exit 2
}

read_rootfs_value() {
  local key="$1"
  awk -v wanted="$key" '
    /^rootfs:$/ { in_rootfs=1; next }
    in_rootfs && /^[^[:space:]#]/ { exit }
    in_rootfs && $1 == wanted ":" {
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  ' "$CONFIG"
}

ARCHITECTURE="$(read_rootfs_value architecture)"
SUITE="$(read_rootfs_value suite)"
VARIANT="$(read_rootfs_value variant)"
MIRROR="$(read_rootfs_value mirror)"
SNAPSHOT="$(read_rootfs_value snapshot)"
DESTINATION="${DESTINATION:-$ROOT/build/rootfs/$TARGET}"

[[ "$ARCHITECTURE" =~ ^(amd64|arm64)$ ]] || {
  echo "Target $TARGET has no supported rootfs architecture" >&2
  exit 2
}
[[ "$SUITE" =~ ^[a-z0-9-]+$ && "$VARIANT" == minbase ]] || {
  echo "Target $TARGET has invalid rootfs suite or variant" >&2
  exit 2
}
[[ "$SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
  echo "Target $TARGET has invalid snapshot timestamp" >&2
  exit 2
}
EXPECTED_MIRROR="https://snapshot.debian.org/archive/debian/$SNAPSHOT"
[[ "$MIRROR" == "$EXPECTED_MIRROR" ]] || {
  echo "Target $TARGET mirror does not match its snapshot timestamp" >&2
  exit 2
}
[[ "$(id -u)" -eq 0 ]] || {
  echo "Root privileges are required to run debootstrap" >&2
  exit 1
}
command -v debootstrap >/dev/null || {
  echo "debootstrap is required" >&2
  exit 1
}
[[ ! -e "$DESTINATION" ]] || {
  echo "Destination already exists: $DESTINATION" >&2
  exit 1
}

mkdir -p "$(dirname "$DESTINATION")"
TEMP_DIR="$(mktemp -d "$(dirname "$DESTINATION")/.rootfs-$TARGET.XXXXXX")"
debootstrap \
  --arch="$ARCHITECTURE" \
  --variant="$VARIANT" \
  "$SUITE" \
  "$TEMP_DIR" \
  "$MIRROR"

[[ -x "$TEMP_DIR/bin/bash" ]] || {
  echo "Bootstrap completed without an executable /bin/bash" >&2
  exit 1
}

cat >"$TEMP_DIR/etc/apt/apt.conf.d/99ashipaos-snapshot" <<EOF
Acquire::Check-Valid-Until "false";
EOF
printf '%s\n' "deb $MIRROR $SUITE main" >"$TEMP_DIR/etc/apt/sources.list"
printf '%s\n' "$SNAPSHOT" >"$TEMP_DIR/etc/ashipaos-debian-snapshot"

mv -- "$TEMP_DIR" "$DESTINATION"
TEMP_DIR=""
echo "Bootstrapped $TARGET ($ARCHITECTURE, $SUITE, $SNAPSHOT) at $DESTINATION"
