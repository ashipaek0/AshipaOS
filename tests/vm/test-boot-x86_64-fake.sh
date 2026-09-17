#!/usr/bin/env bash
# Regression tests for marker-triggered QEMU shutdown status handling.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tests/vm/boot-x86_64.sh"
MARKER_SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/evidence"
printf image > "$TMP/image.img"
printf code > "$TMP/OVMF_CODE.fd"
printf vars > "$TMP/OVMF_VARS.fd"

grep -q 'ExecStart=/usr/bin/printf' "$MARKER_SCRIPT"
grep -q 'StandardOutput=journal+console' "$MARKER_SCRIPT"
grep -q 'StandardError=journal+console' "$MARKER_SCRIPT"
! grep -qE '^(TTYPath|TTYReset|TTYVHangup|TTYVTDisallocate)=' "$MARKER_SCRIPT"
grep -q 'After=multi-user.target' "$MARKER_SCRIPT"
grep -q 'graphical.target.wants' "$MARKER_SCRIPT"
grep -q 'WantedBy=graphical.target' "$MARKER_SCRIPT"
! grep -q 'multi-user.target.wants' "$MARKER_SCRIPT"
grep -q 'rootfs/usr/bin/printf' "$MARKER_SCRIPT"
! grep -q 'ExecStart=/bin/sh' "$MARKER_SCRIPT"
! grep -q '> /dev/ttyS0' "$MARKER_SCRIPT"
printf 'fake-marker-config: PASS\n'

cat > "$TMP/bin/qemu-system-x86_64" <<'FAKE_QEMU'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "--version" ]]; then
    printf 'QEMU emulator version 0.0-fake\n'
    exit 0
fi
serial=''
have_code_pflash=0
have_vars_pflash=0
for arg in "$@"; do
    [[ "$arg" == file:* ]] && serial=${arg#file:}
    [[ "$arg" == if=pflash,format=raw,readonly=on,file=* ]] && have_code_pflash=1
    [[ "$arg" == if=pflash,format=raw,file=* ]] && have_vars_pflash=1
    [[ "$arg" == -bios* ]] && { printf 'fake QEMU received forbidden -bios\n' >&2; exit 98; }
done
(( have_code_pflash == 1 )) || { printf 'fake QEMU did not receive readonly pflash code\n' >&2; exit 98; }
(( have_vars_pflash == 1 )) || { printf 'fake QEMU did not receive writable pflash vars\n' >&2; exit 98; }
: "${serial:?fake QEMU did not receive a serial log}"
case "${FAKE_QEMU_MODE:?}" in
    positive|positive-kill)
        printf 'ASHIPAOS_BOOT_SUCCESS=1\n' >> "$serial"
        if [[ "$FAKE_QEMU_MODE" == positive-kill ]]; then
            trap ':' TERM
        fi
        while :; do sleep 1; done
        ;;
    nonzero)
        sleep 1
        exit 7
        ;;
    timeout)
        while :; do sleep 1; done
        ;;
    *)
        exit 99
        ;;
esac
FAKE_QEMU
chmod +x "$TMP/bin/qemu-system-x86_64"

run_case() {
    local mode=$1 expected=$2 label=$3 status
    set +e
    PATH="$TMP/bin:$PATH" OVMF_CODE="$TMP/OVMF_CODE.fd" OVMF_VARS="$TMP/OVMF_VARS.fd" \
        FAKE_QEMU_MODE="$mode" ASHIPAOS_VM_TIMEOUT_SECONDS=2 \
        ASHIPAOS_VM_SHUTDOWN_GRACE_SECONDS=1 \
        bash "$SCRIPT" "$TMP/image.img" "$TMP/evidence/$label"
    status=$?
    set -e
    if (( status != expected )); then
        printf 'fake-%s: FAIL (expected %s, got %s)\n' "$label" "$expected" "$status" >&2
        return 1
    fi
    printf 'fake-%s: PASS (status %s)\n' "$label" "$status"
}

run_case positive 0 positive
run_case positive-kill 0 positive-kill
run_case nonzero 1 nonzero
run_case timeout 1 timeout
printf 'test-boot-x86_64-fake: PASS\n'
