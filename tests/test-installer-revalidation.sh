#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/payload" "$tmp/target"
printf compressed > "$tmp/payload/appliance.img.zst"; : > "$tmp/device"
hash=$(sha256sum "$tmp/payload/appliance.img.zst" | awk '{print $1}')
printf 'payload_sha256=%s\npayload_size=10\nimage_sha256=%064d\nimage_size=1\n' "$hash" 1 > "$tmp/payload/appliance.img.manifest"
cat > "$tmp/bin/mount" <<'SH'
#!/bin/bash
printf 'mount\n' >> "$EVENTS"; touch "$MOUNTED"
SH
cat > "$tmp/bin/umount" <<'SH'
#!/bin/bash
printf 'umount\n' >> "$EVENTS"; rm -f "$MOUNTED"
SH
cat > "$tmp/bin/zstd" <<'SH'
#!/bin/bash
[[ ! -e "$MOUNTED" ]] || exit 2
printf 'zstd\n' >> "$EVENTS"
exit 67
SH
cat > "$tmp/bin/dd" <<'SH'
#!/bin/bash
printf 'dd\n' >> "$EVENTS"
exit 0
SH
cat > "$tmp/bin/selector" <<'SH'
#!/bin/bash
[[ ! -e "$MOUNTED" ]] || exit 3
printf 'revalidate\n' >> "$EVENTS"
printf '%s\n' "$TARGET_DEVICE"
SH
chmod +x "$tmp/bin/"*
export EVENTS="$tmp/events" MOUNTED="$tmp/mounted" PATH="$tmp/bin:$PATH" TARGET_DEVICE="$tmp/device" TARGET_ROOT="$tmp/target" INSTALLER_ROOT="$tmp/payload" TEST_MODE=1 MARKER_TMP_ROOT="$tmp" INSTALL_TEST_SERIAL="$tmp/serial" SELECTOR_TEST_SCRIPT="$tmp/bin/selector"
# The fake zstd deliberately aborts before any write. We inspect the actual
# install.sh control flow: nothing is mounted before the final selector call.
if "$root/installer/install.sh" > "$tmp/out" 2>&1; then echo 'fake stream unexpectedly completed' >&2; exit 1; fi
python3 - "$tmp/events" <<'PY'
import sys


def check(rows):
    assert rows.count('revalidate') == 1, rows
    assert rows.count('dd') == 1, rows
    assert rows.count('zstd') == 1, rows
    assert len(rows) == 3, rows  # Reject stray mounts or other events.
    assert rows[0] == 'revalidate', rows
    assert set(rows[1:]) == {'dd', 'zstd'}, rows


check(open(sys.argv[1]).read().splitlines())
# Both pipeline processes may start first; neither may precede revalidation.
check(['revalidate', 'dd', 'zstd'])
check(['revalidate', 'zstd', 'dd'])
PY
[[ ! -e "$tmp/mounted" ]]
