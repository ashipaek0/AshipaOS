#!/usr/bin/env bash
# Layer 0 STATIC: privileged rootfs archive producers must hand ownership back
# to the sudo caller, while direct-root and unsafe-value behavior stay explicit.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/scripts/rootfs-ownership.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$HELPER" ]] || fail "ownership helper exists"
for producer in \
  "$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh" \
  "$ROOT/layers/layer5-application/scripts/build-application.sh" \
  "$ROOT/layers/layer2-image/scripts/build-image.sh"; do
  # shellcheck disable=SC2016 # literal source line, not an expansion
  grep -Fq 'source "$REPO_ROOT/scripts/rootfs-ownership.sh"' "$producer" \
    || fail "$producer sources ownership helper"
  grep -Fq 'rootfs_output_owner' "$producer" || fail "$producer restores ownership"
done

# Invalid or partial sudo identity metadata is rejected before chown.
if (SUDO_UID=not-a-uid SUDO_GID=1000 bash -c "source '$HELPER'; rootfs_output_owner") 2>/dev/null; then
  fail "non-numeric SUDO_UID rejected"
fi
if (SUDO_UID=1000 env -u SUDO_GID bash -c "source '$HELPER'; rootfs_output_owner") 2>/dev/null; then
  fail "partial sudo identity rejected"
fi
if (SUDO_UID=4294967296 SUDO_GID=1000 bash -c "source '$HELPER'; rootfs_output_owner") 2>/dev/null; then
  fail "out-of-range ownership rejected"
fi
if (SUDO_UID=999999999999999999999999 SUDO_GID=1000 bash -c "source '$HELPER'; rootfs_output_owner") 2>/dev/null; then
  fail "oversized ownership rejected"
fi

# A direct-root invocation with no sudo metadata is deliberately a no-op.
env -u SUDO_UID -u SUDO_GID bash -c "source '$HELPER'; rootfs_output_owner"

if [[ $EUID -eq 0 ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  touch "$tmp/archive"
  SUDO_UID="$(id -u)" SUDO_GID="$(id -g)" bash -c \
    "source '$HELPER'; rootfs_output_owner '$tmp/archive' '$tmp'"
  [[ "$(stat -c '%u:%g' "$tmp/archive")" == "$(id -u):$(id -g)" ]] \
    || fail "archive ownership restored"
  [[ "$(stat -c '%u:%g' "$tmp")" == "$(id -u):$(id -g)" ]] \
    || fail "archive directory ownership restored"
fi
printf 'test-rootfs-ownership: PASS\n'
