#!/usr/bin/env bash
# Stage 2 VM gate: boot the freshly-built x86_64 Layer 2 image in UEFI QEMU.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE="${1:-}"
EVIDENCE_DIR="${2:-${GITHUB_WORKSPACE:-$REPO_ROOT}/output/evidence/vm-x86_64}"
TIMEOUT_SECONDS="${ASHIPAOS_VM_TIMEOUT_SECONDS:-120}"
SHUTDOWN_GRACE_SECONDS="${ASHIPAOS_VM_SHUTDOWN_GRACE_SECONDS:-10}"

die() { printf '[boot-x86_64] ERROR: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s <x86_64-image> [evidence-directory]\n' "$(basename "$0")"; }

[[ -n "$IMAGE" ]] || { usage >&2; exit 2; }
[[ -f "$IMAGE" ]] || die "image not found: $IMAGE"
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || die 'ASHIPAOS_VM_TIMEOUT_SECONDS must be a positive integer'
(( TIMEOUT_SECONDS <= 600 )) || die 'VM timeout must be <= 600 seconds'
[[ "$SHUTDOWN_GRACE_SECONDS" =~ ^[1-9][0-9]*$ ]] || die 'ASHIPAOS_VM_SHUTDOWN_GRACE_SECONDS must be a positive integer'
(( SHUTDOWN_GRACE_SECONDS <= 60 )) || die 'VM shutdown grace must be <= 60 seconds'
command -v qemu-system-x86_64 >/dev/null || die 'qemu-system-x86_64 is required'

is_non_secure_code() {
    local name=${1##*/}
    [[ "$name" == OVMF_CODE*.fd ]] || return 1
    [[ "$name" != *.[Mm][Ss].fd && "$name" != *.[Ss][Ee][Cc][Bb][Oo][Oo][Tt].fd ]]
}

find_ovmf_code() {
    local candidate
    # Ubuntu/Debian's OVMF_CODE_* files are pflash code images, not -bios ROMs.
    for candidate in \
        "${OVMF_CODE:-}" \
        /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/ovmf/OVMF_CODE_4M.fd /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE_4M.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
        [[ -n "$candidate" && -s "$candidate" ]] && is_non_secure_code "$candidate" && {
            printf '%s\n' "$candidate"; return
        }
    done
    while IFS= read -r candidate; do
        [[ -s "$candidate" ]] && is_non_secure_code "$candidate" && {
            printf '%s\n' "$candidate"; return
        }
    done < <(find /usr/share -type f -iname 'OVMF_CODE*.fd' -print 2>/dev/null | sort -f)
    return 1
}

find_ovmf_vars() {
    local code=$1 candidate suffix
    suffix=${code##*OVMF_CODE}
    for candidate in \
        "${OVMF_VARS:-}" \
        "${code%/*}/OVMF_VARS${suffix}"; do
        [[ -n "$candidate" && -s "$candidate" && "$candidate" != *.[Mm][Ss].fd && "$candidate" != *.[Ss][Ee][Cc][Bb][Oo][Oo][Tt].fd ]] && {
            printf '%s\n' "$candidate"; return
        }
    done
    return 1
}

mkdir -p "$EVIDENCE_DIR"
SERIAL_LOG="$EVIDENCE_DIR/serial.log"
QEMU_LOG="$EVIDENCE_DIR/qemu.log"
COMMAND_FILE="$EVIDENCE_DIR/qemu-command.txt"
VERSION_FILE="$EVIDENCE_DIR/qemu-version.txt"
SHA_FILE="$EVIDENCE_DIR/image.sha256"
OVMF=$(find_ovmf_code) || die 'usable non-secure-boot OVMF_CODE firmware not found'
OVMF_VARS_TEMPLATE=$(find_ovmf_vars "$OVMF" || true)
OVMF_VARS=''
if [[ -n "$OVMF_VARS_TEMPLATE" ]]; then
    OVMF_VARS="$EVIDENCE_DIR/OVMF_VARS.fd"
    cp -- "$OVMF_VARS_TEMPLATE" "$OVMF_VARS" || die 'could not copy OVMF_VARS template'
fi
QEMU_FIRMWARE_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF")
[[ -n "$OVMF_VARS" ]] && QEMU_FIRMWARE_ARGS+=(-drive "if=pflash,format=raw,file=$OVMF_VARS")
QEMU_ARGS=(-machine q35 -accel tcg -cpu max -m 1024 "${QEMU_FIRMWARE_ARGS[@]}" \
    -drive "format=raw,if=virtio,file=$IMAGE,readonly=on" \
    -nographic -serial stdio -monitor none -no-reboot)

sha256sum "$IMAGE" > "$SHA_FILE"
qemu-system-x86_64 --version > "$VERSION_FILE" 2>&1 || true
printf '%q ' qemu-system-x86_64 "${QEMU_ARGS[@]}" > "$COMMAND_FILE"
printf '> %q 2> %q\n' "$SERIAL_LOG" "$QEMU_LOG" >> "$COMMAND_FILE"

stop_qemu() {
    local second
    kill -TERM "$QEMU_PID" 2>/dev/null || true
    for ((second=0; second<SHUTDOWN_GRACE_SECONDS; second++)); do
        if ! kill -0 "$QEMU_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$QEMU_PID" 2>/dev/null; then
        kill -KILL "$QEMU_PID" 2>/dev/null || true
    fi
    wait "$QEMU_PID" 2>/dev/null
}

set +e
: > "$SERIAL_LOG"
qemu-system-x86_64 "${QEMU_ARGS[@]}" >"$SERIAL_LOG" 2>"$QEMU_LOG" &
QEMU_PID=$!
QEMU_STATUS=0
MARKER_OBSERVED=0
for ((second=0; second<TIMEOUT_SECONDS; second++)); do
    if grep -Eiq 'kernel panic|panic:|emergency mode|failed to start emergency' "$SERIAL_LOG" "$QEMU_LOG"; then
        QEMU_STATUS=1
        break
    fi
    if grep -Fxq 'ASHIPAOS_BOOT_SUCCESS=1' "$SERIAL_LOG"; then
        MARKER_OBSERVED=1
        stop_qemu
        QEMU_STATUS=$?
        break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        wait "$QEMU_PID"
        QEMU_STATUS=$?
        break
    fi
    sleep 1
done
if kill -0 "$QEMU_PID" 2>/dev/null; then
    stop_qemu
    QEMU_STATUS=124
fi
set -e

cat "$QEMU_LOG" >> "$SERIAL_LOG" 2>/dev/null || true
if grep -Eiq 'kernel panic|panic:|emergency mode|failed to start emergency' "$SERIAL_LOG"; then
    die 'panic or emergency-mode text detected'
fi
if (( QEMU_STATUS == 124 )); then
    die "QEMU timed out after ${TIMEOUT_SECONDS}s"
fi
if (( MARKER_OBSERVED )); then
    case "$QEMU_STATUS" in
        0|137|143) ;;
        *) die "QEMU exited with unexpected marker-shutdown status $QEMU_STATUS" ;;
    esac
else
    (( QEMU_STATUS == 0 )) || die "QEMU exited with status $QEMU_STATUS"
fi
grep -Fxq 'ASHIPAOS_BOOT_SUCCESS=1' "$SERIAL_LOG" || die 'userspace boot marker not observed'
printf '[boot-x86_64] PASS: userspace boot marker observed\n'
