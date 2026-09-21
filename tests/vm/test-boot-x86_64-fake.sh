#!/usr/bin/env bash
# Regression tests for buffered serial and marker-triggered QEMU shutdown.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tests/vm/boot-x86_64.sh"
MARKER_SCRIPT="$ROOT/layers/layer1-rootfs/scripts/build-rootfs.sh"
ROOTFS_OVERLAY="$ROOT/rootfs-overlay"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/evidence"
printf image > "$TMP/image.img"
printf code > "$TMP/OVMF_CODE.fd"
printf vars > "$TMP/OVMF_VARS.fd"

grep -q 'Requires=ashipaos-display.service' "$ROOTFS_OVERLAY/etc/systemd/system/ashipaos-boot-success.service"
grep -q 'ASHIPAOS_BOOT_SUCCESS=1' "$ROOTFS_OVERLAY/etc/systemd/system/ashipaos-boot-success.service"
marker_guard=$(grep 'if \[\[ "\$product_arch"' "$MARKER_SCRIPT")
[[ "$marker_guard" == *'"x86_64"'* && "$marker_guard" == *'"amd64"'* ]]
[[ "$marker_guard" != *'"arm64"'* && "$marker_guard" != *'"armhf"'* ]]
! grep -q 'ashipaos-boot-success.service' "$MARKER_SCRIPT"
printf 'fake-marker-config: PASS\n'

cat > "$TMP/bin/qemu-system-x86_64" <<'FAKE_QEMU'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "--version" ]]; then
    printf 'QEMU emulator version 0.0-fake\n'
    exit 0
fi
[[ "${LD_PRELOAD:-}" == *libstdbuf* ]] || {
    printf 'fake QEMU was not launched through stdbuf\n' >&2
    exit 97
}
serial_mode=''
have_code_pflash=0
have_vars_pflash=0
for arg in "$@"; do
    if [[ "$arg" == -serial ]]; then
        serial_mode=expecting
    elif [[ "$serial_mode" == expecting && "$arg" == stdio ]]; then
        serial_mode=stdio
    elif [[ "$serial_mode" == expecting && "$arg" == file:* ]]; then
        printf 'fake QEMU received forbidden -serial file backend\n' >&2
        exit 98
    fi
    [[ "$arg" == if=pflash,format=raw,readonly=on,file=* ]] && have_code_pflash=1
    [[ "$arg" == if=pflash,format=raw,file=* ]] && have_vars_pflash=1
    [[ "$arg" == -bios* ]] && { printf 'fake QEMU received forbidden -bios\n' >&2; exit 98; }
done
(( have_code_pflash == 1 )) || { printf 'fake QEMU did not receive readonly pflash code\n' >&2; exit 98; }
(( have_vars_pflash == 1 )) || { printf 'fake QEMU did not receive writable pflash vars\n' >&2; exit 98; }
[[ "$serial_mode" == stdio ]] || { printf 'fake QEMU did not receive -serial stdio\n' >&2; exit 98; }
case "${FAKE_QEMU_MODE:?}" in
    positive|positive-kill)
        printf 'ASHIPAOS_BOOT_SUCCESS=1\n'
        if [[ "$FAKE_QEMU_MODE" == positive-kill ]]; then
            trap ':' TERM
        fi
        while :; do sleep 1; done
        ;;
    positive-crlf)
        printf 'ASHIPAOS_BOOT_SUCCESS=1\r\n'
        while :; do sleep 1; done
        ;;
    marker-after-shutdown)
        trap 'printf "ASHIPAOS_BOOT_SUCCESS=1\\n"; exit 0' TERM
        while :; do sleep 1; done
        ;;
    marker-after-shutdown-crlf)
        trap 'printf "ASHIPAOS_BOOT_SUCCESS=1\\r\\n"; exit 0' TERM
        while :; do sleep 1; done
        ;;
    nonzero)
        sleep 1
        exit 7
        ;;
    nonzero-marker)
        printf 'ASHIPAOS_BOOT_SUCCESS=1\n'
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
    local command_file="$TMP/evidence/$label/qemu-command.txt"
    grep -Fq -- 'stdbuf -o0 -e0 qemu-system-x86_64' "$command_file"
    grep -Fq -- '-serial stdio' "$command_file"
    ! grep -Fq -- '-serial file:' "$command_file"
    local expected_redirection="> $TMP/evidence/$label/serial.log 2> $TMP/evidence/$label/qemu.log"
    grep -Fq -- "$expected_redirection" "$command_file"
    printf 'fake-%s: PASS (status %s)\n' "$label" "$status"
}

run_case positive 0 positive
run_case positive-kill 0 positive-kill
run_case positive-crlf 0 positive-crlf
run_case marker-after-shutdown 0 marker-after-shutdown
run_case marker-after-shutdown-crlf 0 marker-after-shutdown-crlf
run_case nonzero 1 nonzero
run_case nonzero-marker 1 nonzero-marker
run_case timeout 1 timeout
printf 'test-boot-x86_64-fake: PASS\n'
