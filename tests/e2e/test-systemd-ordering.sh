#!/usr/bin/env bash
# E2E: every systemd unit this image installs verifies cleanly against the
# REAL systemd-fstab-generator and systemd-analyze, with zero ordering
# cycles. Exists because ashipaos-storage-grow.service had a real one
# (evidence/amlogic/a95x-f3-air/boot-2026-09-25c/): as an ordinary service
# (no DefaultDependencies=no) pulled in ahead of storage.mount (a
# local-fs.target member) by its own fstab line, it created
# sysinit.target -> local-fs.target -> storage.mount -> this service ->
# sysinit.target, and systemd resolved it by silently dropping
# local-fs.target from the boot transaction -- STORAGE, and everything that
# depends on it (the app's config directory), never mounted, on every boot.
# A grep-based static check cannot see this; it takes the real ordering
# solver to prove it.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY="$ROOT/rootfs-overlay"
APP_UNITS="$ROOT/layers/layer5-application/files/etc/systemd/system"
IMAGE_CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

FSTAB_GENERATOR=/usr/lib/systemd/system-generators/systemd-fstab-generator
for cmd in systemd-analyze python3; do
    command -v "$cmd" >/dev/null || { echo "SKIP: $cmd is required for the systemd-ordering E2E" >&2; exit 0; }
done
[[ -x "$FSTAB_GENERATOR" ]] || { echo "SKIP: systemd-fstab-generator is required for the systemd-ordering E2E" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The exact fstab layers/layer2-image/scripts/build-image.sh's
# write_shared_fstab() writes, with the real configured labels.
read -r BOOT_LABEL STORAGE_LABEL < <(python3 - "$IMAGE_CONFIG" <<'PY'
import sys, yaml
c = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["partitions"]
print(c["boot"]["label"], c["storage"]["label"])
PY
)
mkdir -p "$TMP/etc/systemd/system" "$TMP/run/systemd/generator"
{
    printf 'LABEL=%s\t/boot/firmware\tvfat\tdefaults,nofail,umask=0022\t0\t0\n' "$BOOT_LABEL"
    printf 'LABEL=%s\t/storage\text4\tdefaults,noatime,nofail,x-systemd.growfs,x-systemd.requires=ashipaos-storage-grow.service\t0\t2\n' "$STORAGE_LABEL"
} >"$TMP/etc/fstab"

# Every unit this image installs (Layer 1 overlay + Layer 5 application),
# with ExecStart/ExecStop binaries stubbed out: verify checks the units are
# executable, but only their ORDERING is what this test is proving.
mkdir -p "$TMP/bin"
for unit in "$OVERLAY"/etc/systemd/system/*.service "$APP_UNITS"/*.service; do
    [[ -f "$unit" ]] || continue
    name="$(basename "$unit")"
    sed -E 's#=(/usr/[a-zA-Z0-9_./-]+)#='"$TMP"'/bin/stub#g' "$unit" >"$TMP/etc/systemd/system/$name"
done
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/stub"
chmod 0755 "$TMP/bin/stub"

# The real generator, against the real fstab above -- exactly what boots.
SYSTEMD_FSTAB="$TMP/etc/fstab" "$FSTAB_GENERATOR" \
    "$TMP/run/systemd/generator" "$TMP/run/systemd/generator" "$TMP/run/systemd/generator" >/dev/null 2>&1
[[ -f "$TMP/run/systemd/generator/storage.mount" ]] || fail "fstab generator did not produce storage.mount; test setup is broken"

mapfile -t units < <(cd "$OVERLAY/etc/systemd/system" && ls -- *.service 2>/dev/null; cd "$APP_UNITS" && ls -- *.service 2>/dev/null)
out="$(SYSTEMD_UNIT_PATH="$TMP/etc/systemd/system:$TMP/run/systemd/generator:" \
    systemd-analyze verify local-fs.target multi-user.target sysinit.target storage.mount "${units[@]}" 2>&1)" || {
    echo "$out" >&2
    fail "systemd-analyze verify found a real problem (ordering cycle or otherwise) -- see output above"
}
# Even a 0-exit run can carry warnings on stderr; a cycle specifically always
# prints "ordering cycle", so a targeted check catches a cycle systemd
# resolved without failing the whole verify (as it did for the bug above).
! grep -qi 'ordering cycle' <<<"$out" || { echo "$out" >&2; fail "an ordering cycle was found and silently resolved"; }

printf '%s\n' 'PASS: systemd unit ordering E2E'
