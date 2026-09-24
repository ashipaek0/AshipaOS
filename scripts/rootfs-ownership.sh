#!/usr/bin/env bash
# Restore ownership of privileged rootfs outputs for the invoking sudo user.
# Source this file from archive producers; it intentionally performs no action
# for direct-root invocations that have no SUDO_UID/SUDO_GID context.

rootfs_output_owner() {
    local uid="${SUDO_UID-}" gid="${SUDO_GID-}" value max=4294967295

    if [[ -z "$uid" && -z "$gid" ]]; then
        return 0
    fi
    [[ -n "$uid" && -n "$gid" ]] || {
        printf 'unsafe rootfs output ownership: SUDO_UID and SUDO_GID must be set together\n' >&2
        return 1
    }
    for value in "$uid" "$gid"; do
        [[ "$value" =~ ^[0-9]+$ ]] || {
            printf 'unsafe rootfs output ownership value: %s\n' "$value" >&2
            return 1
        }
        # Compare as bounded decimal text; arithmetic expansion can wrap on
        # oversized values and must not turn an attacker-controlled ID valid.
        local normalized="${value#${value%%[!0]*}}"
        [[ -n "$normalized" ]] || normalized=0
        (( ${#normalized} < 10 || (${#normalized} == 10 && "$normalized" <= "$max") )) || {
            printf 'unsafe rootfs output ownership value: %s\n' "$value" >&2
            return 1
        }
    done

    # A non-root caller cannot have created the privileged archive. This keeps
    # the helper harmless when sourced by the intentionally unprivileged layer.
    [[ $EUID -eq 0 ]] || return 0

    local path
    for path in "$@"; do
        [[ -e "$path" || -L "$path" ]] || {
            printf 'rootfs output does not exist: %s\n' "$path" >&2
            return 1
        }
        chown -- "$uid:$gid" "$path"
    done
}
