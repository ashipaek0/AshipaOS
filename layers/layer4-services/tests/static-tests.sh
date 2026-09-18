#!/usr/bin/env bash
# Static and negative tests for Layer 4 x86_64 service policy.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_SCRIPT="$LAYER_DIR/scripts/build-services.sh"
CONFIG_FILE="$LAYER_DIR/config/services-config.yaml"
PASSED=0
FAILED=0

pass() { printf '✓ %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '✗ %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { if "$@"; then pass "$1"; else fail "$1"; fi; }
contains() { grep -q -- "$1" "$2"; }
fixed_contains() { grep -Fq -- "$1" "$2"; }
not_contains() { ! grep -q -- "$1" "$2"; }

printf 'Running Layer 4 Static Tests...\n================================\n'
check test -x "$BUILD_SCRIPT"
check test -f "$CONFIG_FILE"
check contains '^#!/usr/bin/env bash$' "$BUILD_SCRIPT"
check contains 'set -Eeuo pipefail' "$BUILD_SCRIPT"
check contains 'systemd-analyze verify' "$BUILD_SCRIPT"
check contains 'systemctl --root=' "$BUILD_SCRIPT"
check contains 'packages_changed": false' "$BUILD_SCRIPT"
check contains 'Layer 4 is x86_64-only' "$BUILD_SCRIPT"
check contains 'tar --create --gzip' "$BUILD_SCRIPT"
for pseudo_dir in dev proc sys run; do
    check fixed_contains "--exclude='./$pseudo_dir/*'" "$BUILD_SCRIPT"
done
check fixed_contains 'tar --extract --gzip --file "$ROOTFS_TARBALL" --directory "$ROOTFS"' "$BUILD_SCRIPT"
check contains 'unsafe rootfs tar member' "$BUILD_SCRIPT"
check contains 'policy.disable_unlisted must be true' "$BUILD_SCRIPT"
check contains 'disabled unit is not a real unit file' "$BUILD_SCRIPT"
check contains 'disabled unit is missing \[Unit\]' "$BUILD_SCRIPT"
check contains 'failed to disable present distro unit' "$BUILD_SCRIPT"
check not_contains '|| true' "$BUILD_SCRIPT"
check not_contains 'etc/systemd/system"; do' "$BUILD_SCRIPT"
check contains '^  enabled:$' "$CONFIG_FILE"
check contains '^  disabled:$' "$CONFIG_FILE"
check contains '^target: x86_64$' "$CONFIG_FILE"
check contains '^  preset_file:' "$CONFIG_FILE"
check contains '^  disable_unlisted: true$' "$CONFIG_FILE"
check not_contains '\\.stub' "$BUILD_SCRIPT"
check not_contains 'ExecStart=/bin/true' "$BUILD_SCRIPT"
check not_contains '^    - ssh$' "$CONFIG_FILE"
check not_contains '^    - cron$' "$CONFIG_FILE"

list_output="$($BUILD_SCRIPT --list)"
[[ "$list_output" == *"Enabled services:"* && "$list_output" == *"systemd-journald.service"* ]] && pass '--list emits configured enabled services' || fail '--list emits configured enabled services'
$BUILD_SCRIPT --validate >/dev/null && pass '--validate accepts config semantics' || fail '--validate accepts config semantics'

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
cp -a "$LAYER_DIR" "$tmp_dir/layer4-services"
sed -i 's/^  disable_unlisted: true$/  disable_unlisted: false/' \
    "$tmp_dir/layer4-services/config/services-config.yaml"
if "$tmp_dir/layer4-services/scripts/build-services.sh" --validate >/dev/null 2>&1; then
    fail 'config rejects disable_unlisted=false'
else
    pass 'config rejects disable_unlisted=false'
fi

unsafe_tar="$tmp_dir/unsafe.tar.gz"
python3 - "$unsafe_tar" <<'PYEOF'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], 'w:gz') as archive:
    member = tarfile.TarInfo('../escape')
    member.size = 4
    archive.addfile(member, io.BytesIO(b'test'))
PYEOF
if "$BUILD_SCRIPT" "$unsafe_tar" x86_64 >/dev/null 2>&1; then
    fail 'tar traversal member is rejected before extraction'
else
    pass 'tar traversal member is rejected before extraction'
fi

if "$BUILD_SCRIPT" /dev/null a95x-f3-air >/dev/null 2>&1; then
    fail 'target restriction rejects ARM target'
else
    pass 'target restriction rejects ARM target'
fi
if "$BUILD_SCRIPT" /definitely/missing.tar.gz x86_64 >/dev/null 2>&1; then
    fail 'missing rootfs failure path is rejected'
else
    pass 'missing rootfs failure path is rejected'
fi

printf '================================\nResults: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
