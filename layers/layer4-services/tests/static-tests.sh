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

# The enabled policy may only name units supplied by Layer 1's systemd package.
# Keep this explicit so an unavailable optional unit cannot silently become a
# Layer 4 requirement again.
layer1_config="$LAYER_DIR/../layer1-rootfs/config/rootfs-config.yaml"
if grep -q '^    - systemd$' "$layer1_config"; then
    pass 'Layer 1 declares the systemd package for enabled Layer 4 units'
else
    fail 'Layer 1 declares the systemd package for enabled Layer 4 units'
fi
unsupported_enabled=0
while IFS= read -r unit; do
    case "$unit" in
        systemd-journald.service|systemd-logind.service|systemd-networkd.service|getty@tty1.service)
            ;;
        *)
            printf 'Unsupported enabled Layer 4 unit: %s\\n' "$unit" >&2
            unsupported_enabled=1
            ;;
    esac
done < <(awk '/^  enabled:/{in_section=1; next} in_section && /^  [[:alnum:]_-]+:/{exit} in_section && $1 == "-"{print $2}' "$CONFIG_FILE")
if [[ "$unsupported_enabled" -eq 0 ]]; then
    pass 'enabled Layer 4 units are provided by Layer 1 systemd'
else
    fail 'enabled Layer 4 units are provided by Layer 1 systemd'
fi

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

# Every configured unit list is untrusted input. Exercise absolute paths,
# slash traversal, and dot-dot values in enabled, disabled, and required lists.
for section in enabled disabled required_services; do
    for unsafe_unit in '/etc/evil.service' 'foo/../../evil.service' '../evil.service' 'foo..service'; do
        unsafe_layer="$tmp_dir/unsafe-${section}-$(printf '%s' "$unsafe_unit" | tr '/.' '__')"
        cp -a "$LAYER_DIR" "$unsafe_layer"
        python3 - "$CONFIG_FILE" "$unsafe_layer/config/services-config.yaml" "$section" "$unsafe_unit" <<'PYEOF'
import sys

source, destination, section, replacement = sys.argv[1:]
lines = open(source, encoding='utf-8').read().splitlines(True)
in_section = False
replaced = False
for index, line in enumerate(lines):
    if line == f'  {section}:\n':
        in_section = True
        continue
    if in_section and line.startswith('  ') and not line.startswith('    '):
        in_section = False
    if in_section and not replaced and line.startswith('    - '):
        lines[index] = f'    - {replacement}\n'
        replaced = True
if not replaced:
    raise SystemExit(f'could not replace first item in {section}')
open(destination, 'w', encoding='utf-8').writelines(lines)
PYEOF
        if "$unsafe_layer/scripts/build-services.sh" --validate >/dev/null 2>&1; then
            fail "$section rejects unsafe unit $unsafe_unit"
        else
            pass "$section rejects unsafe unit $unsafe_unit"
        fi
    done
done

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

# A configured template instance must validate against the distro template,
# while systemctl still receives the configured instance name.
template_test="$tmp_dir/template-test"
mkdir -p "$template_test/bin"
cp -a "$LAYER_DIR" "$template_test/layer4-services"
cat > "$template_test/layer4-services/config/services-config.yaml" <<'EOF'
target: x86_64
services:
  enabled:
    - getty@tty1.service
  disabled:
    - getty@tty2.service
  required_services:
    - getty@tty1.service
    - getty@tty2.service
default_target: multi-user.target
policy:
  preset_file: /etc/systemd/system-preset/ashipaos.preset
  disable_unlisted: true
EOF
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${TEST_LOG:?}"\n' \
    > "$template_test/bin/systemd-analyze"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${TEST_LOG:?}"\n' \
    > "$template_test/bin/systemctl"
chmod +x "$template_test/bin/systemd-analyze" "$template_test/bin/systemctl"
template_rootfs="$template_test/with-template.tar.gz"
missing_template_rootfs="$template_test/without-template.tar.gz"
python3 - "$template_rootfs" "$missing_template_rootfs" <<'PYEOF'
import io
import sys
import tarfile

def write_rootfs(path, include_template):
    with tarfile.open(path, 'w:gz') as archive:
        for name in ('etc/systemd', 'usr/lib/systemd/system'):
            info = tarfile.TarInfo(name)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            archive.addfile(info)
        if include_template:
            body = b'[Unit]\nDescription=Getty\n[Install]\nWantedBy=getty.target\n'
            info = tarfile.TarInfo('usr/lib/systemd/system/getty@.service')
            info.size = len(body)
            archive.addfile(info, io.BytesIO(body))

write_rootfs(sys.argv[1], True)
write_rootfs(sys.argv[2], False)
PYEOF
export TEST_LOG="$template_test/systemctl.log"
PATH="$template_test/bin:$PATH" \
    "$template_test/layer4-services/scripts/build-services.sh" "$template_rootfs" x86_64 \
    >/dev/null 2>&1 \
    && pass 'templated instance resolves to distro template' \
    || fail 'templated instance resolves to distro template'
if grep -Fq -- 'enable getty@tty1.service' "$TEST_LOG" && \
   grep -Fq -- 'disable getty@tty2.service' "$TEST_LOG" && \
   ! grep -Fq -- 'enable getty@.service' "$TEST_LOG" && \
   ! grep -Fq -- 'disable getty@.service' "$TEST_LOG"; then
    pass 'systemctl enable/disable preserve templated instance names'
else
    fail 'systemctl enable/disable preserve templated instance names'
fi
if PATH="$template_test/bin:$PATH" \
    "$template_test/layer4-services/scripts/build-services.sh" "$missing_template_rootfs" x86_64 \
    >/dev/null 2>&1; then
    fail 'missing template is rejected'
else
    pass 'missing template is rejected'
fi

# A distro unit may have an optional Wants/After dependency that is not shipped
# by the pinned package version. Only that classified diagnostic is tolerated;
# unrelated verifier failures must remain fatal.
optional_test="$tmp_dir/optional-dependency-test"
mkdir -p "$optional_test/bin"
cp -a "$LAYER_DIR" "$optional_test/layer4-services"
cat > "$optional_test/layer4-services/config/services-config.yaml" <<'EOF'
target: x86_64
services:
  enabled:
    - systemd-logind.service
  disabled:
    - bluetooth.service
  required_services:
    - systemd-logind.service
default_target: multi-user.target
policy:
  preset_file: /etc/systemd/system-preset/ashipaos.preset
  disable_unlisted: true
EOF
mkdir -p "$optional_test/rootfs/etc/systemd" "$optional_test/rootfs/usr/lib/systemd/system"
cat > "$optional_test/rootfs/usr/lib/systemd/system/systemd-logind.service" <<'EOF'
[Unit]
Wants=dbus.socket
After=dbus.socket
[Service]
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
tar -czf "$optional_test/rootfs.tar.gz" -C "$optional_test/rootfs" .
cat > "$optional_test/bin/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
printf '%b\n' "${VERIFY_OUTPUT:?}"
exit 1
EOF
cat > "$optional_test/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$optional_test/bin/systemd-analyze" "$optional_test/bin/systemctl"
export VERIFY_OUTPUT='systemd-logind.service: Unit dbus.socket not found.'
if PATH="$optional_test/bin:$PATH" \
    "$optional_test/layer4-services/scripts/build-services.sh" "$optional_test/rootfs.tar.gz" x86_64 \
    >/dev/null 2>&1; then
    pass 'missing optional Wants/After dependency is classified and tolerated'
else
    fail 'missing optional Wants/After dependency is classified and tolerated'
fi
sed -i '/^Wants=dbus\.socket$/a Requires=dbus.socket' \
    "$optional_test/rootfs/usr/lib/systemd/system/systemd-logind.service"
tar -czf "$optional_test/rootfs.tar.gz" -C "$optional_test/rootfs" .
export VERIFY_OUTPUT='systemd-logind.service: Unit dbus.socket not found.'
if PATH="$optional_test/bin:$PATH" \
    "$optional_test/layer4-services/scripts/build-services.sh" "$optional_test/rootfs.tar.gz" x86_64 \
    >/dev/null 2>&1; then
    fail 'missing required dependency is not tolerated'
else
    pass 'missing required dependency is not tolerated'
fi
sed -i '/^Requires=dbus\.socket$/d' \
    "$optional_test/rootfs/usr/lib/systemd/system/systemd-logind.service"
tar -czf "$optional_test/rootfs.tar.gz" -C "$optional_test/rootfs" .
export VERIFY_OUTPUT=$'systemd-logind.service: Unit dbus.socket not found.\nsystemd-logind.service: Unit required.socket not found.'
if PATH="$optional_test/bin:$PATH" \
    "$optional_test/layer4-services/scripts/build-services.sh" "$optional_test/rootfs.tar.gz" x86_64 \
    >/dev/null 2>&1; then
    fail 'unclassified verifier diagnostics remain fatal'
else
    pass 'unclassified verifier diagnostics remain fatal'
fi

printf '================================\nResults: %d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
