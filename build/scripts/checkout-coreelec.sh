#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${ASHIPAOS_BOX_CONFIG:-$ROOT/build/targets/amlogic/boxes/a95x-f3-air.yaml}"
DESTINATION="${1:-$ROOT/amlogic-coreelec-fork/source}"
TEMP_DIR=""

cleanup() {
  set +e
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

read_coreelec_value() {
  local key="$1"
  awk -v wanted="$key" '
    /^coreelec:$/ { in_coreelec=1; next }
    in_coreelec && /^[^[:space:]#]/ { exit }
    in_coreelec && $1 == wanted ":" {
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  ' "$CONFIG"
}

REPOSITORY="$(read_coreelec_value repository)"
REF="$(read_coreelec_value ref)"
COMMIT="$(read_coreelec_value commit)"

if [[ -z "$REPOSITORY" || -z "$REF" || ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Invalid or incomplete CoreELEC pin in $CONFIG" >&2
  exit 1
fi

verify_checkout() {
  local checkout="$1"
  local actual_commit actual_origin
  actual_commit="$(git -C "$checkout" rev-parse HEAD)"
  actual_origin="$(git -C "$checkout" remote get-url origin)"

  [[ "$actual_origin" == "$REPOSITORY" ]] || {
    echo "CoreELEC origin mismatch: expected $REPOSITORY, got $actual_origin" >&2
    return 1
  }
  [[ "$actual_commit" == "$COMMIT" ]] || {
    echo "CoreELEC commit mismatch: expected $COMMIT, got $actual_commit" >&2
    return 1
  }
  git -C "$checkout" symbolic-ref -q HEAD >/dev/null && {
    echo "CoreELEC checkout must have a detached HEAD" >&2
    return 1
  }
  [[ -z "$(git -C "$checkout" status --porcelain)" ]] || {
    echo "CoreELEC checkout has local changes" >&2
    return 1
  }
  if ! git -C "$checkout" show-ref --verify --quiet "refs/tags/$REF"; then
    git -C "$checkout" fetch --quiet --depth 1 origin "refs/tags/$REF:refs/tags/$REF"
  fi
  [[ "$(git -C "$checkout" rev-list -n 1 "refs/tags/$REF")" == "$COMMIT" ]] || {
    echo "CoreELEC tag $REF does not identify $COMMIT" >&2
    return 1
  }
}

if [[ -e "$DESTINATION" ]]; then
  [[ -d "$DESTINATION/.git" ]] || {
    echo "Destination exists but is not a Git checkout: $DESTINATION" >&2
    exit 1
  }
  verify_checkout "$DESTINATION"
  echo "Verified CoreELEC $REF at $COMMIT"
  exit 0
fi

mkdir -p "$(dirname "$DESTINATION")"
TEMP_DIR="$(mktemp -d "$(dirname "$DESTINATION")/.coreelec.XXXXXX")"
git -C "$TEMP_DIR" init --quiet
git -C "$TEMP_DIR" remote add origin "$REPOSITORY"
git -C "$TEMP_DIR" fetch --quiet --depth 1 origin "refs/tags/$REF:refs/tags/$REF"

FETCHED_COMMIT="$(git -C "$TEMP_DIR" rev-list -n 1 "refs/tags/$REF")"
if [[ "$FETCHED_COMMIT" != "$COMMIT" ]]; then
  echo "CoreELEC tag $REF resolved to $FETCHED_COMMIT, expected $COMMIT" >&2
  exit 1
fi

git -C "$TEMP_DIR" checkout --quiet --detach "$COMMIT"
verify_checkout "$TEMP_DIR"
mv -- "$TEMP_DIR" "$DESTINATION"
TEMP_DIR=""
echo "Checked out CoreELEC $REF at $COMMIT"
