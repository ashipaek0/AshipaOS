#!/usr/bin/env bash
# Layer 3 display stack installer. Mutates the x86_64 target rootfs tarball.
# Verification class: BUILD; physical GPU/display verification remains HARDWARE.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
LOCK="$LAYER_DIR/config/packages.lock"
EVIDENCE_DIR="$LAYER_DIR/evidence"
SOURCE_LIST="/etc/apt/sources.list.d/ashipaos-layer3.list"
TEMP_DIR=""

error() { printf '[L3-DISPLAY ERROR] %s\n' "$*" >&2; exit 1; }
log() { printf '[L3-DISPLAY] %s\n' "$*"; }
usage() { printf 'Usage: %s <rootfs-tar.gz> <target>\n' "$(basename "$0")"; }

cleanup() {
    local rootfs="${ROOTFS:-}"
    [[ -n "$rootfs" && -d "$rootfs" ]] || return 0
    for p in dev/pts dev sys proc; do
        mountpoint -q "$rootfs/$p" && umount -l "$rootfs/$p" || true
    done
}

mount_api() {
    local rootfs="$1"
    mount -t proc proc "$rootfs/proc"
    mount --rbind /sys "$rootfs/sys"
    mount --make-rslave "$rootfs/sys"
    mount --rbind /dev "$rootfs/dev"
    mount --make-rslave "$rootfs/dev"
}

run_target() { chroot "$1" "${@:2}"; }

lock_source_line() {
    python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
source = lock["source"]
print("deb [arch=amd64 check-valid-until=no] " + source["uri"] + " " + source["suite"] + " " + " ".join(source["components"]))
PY
}

prepare_apt_state() {
    local rootfs="$1" actual_arch
    actual_arch=$(run_target "$rootfs" dpkg --print-architecture)
    [[ "$actual_arch" == amd64 ]] || error "Layer 3 display requires an amd64 target rootfs, got $actual_arch"

    # debootstrap leaves indexes for its mutable mirror in the target.  APT
    # otherwise retains those lists when the source list is replaced, mixing
    # candidates from two repositories and making valid snapshot dependencies
    # appear uninstallable.
    rm -rf -- "$rootfs/var/lib/apt/lists/"*
    mkdir -p "$rootfs/var/lib/apt/lists/partial" "$rootfs/var/cache/apt/archives/partial"
}

# Emit name, version, architecture, filename and digest from the committed lock.
load_lock() {
    python3 - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
source = lock["source"]
if source != {"uri": source["uri"], "suite": source["suite"], "components": source["components"], "provenance": source["provenance"]}:
    raise SystemExit("packages.lock has unexpected source fields")
for name, item in lock["packages"].items():
    fields = (name, item["version"], item["architecture"], item["filename"], item["sha256"])
    if len(item["sha256"]) != 64 or any(c not in "0123456789abcdef" for c in item["sha256"]):
        raise SystemExit(f"invalid sha256 for {name}")
    print("\t".join(fields))
PY
}

apt_options=(
    -o "Dir::Etc::sourcelist=$SOURCE_LIST"
    -o "Dir::Etc::sourceparts=-"
    -o Acquire::Check-Valid-Until=false
    -o Acquire::By-Hash=force
    -o APT::Architecture=amd64
    -o APT::Architectures=amd64
)

diagnose_apt_state() {
    local rootfs="$1" package
    shift
    # Keep resolver evidence useful but bounded.  awk reads the complete stream,
    # avoiding a producer SIGPIPE, while only emitting the first 240 lines.
    bounded_target() {
        run_target "$rootfs" "$@" 2>&1 | awk 'NR <= 240 { print }' || true
    }

    log "Target APT state immediately before locked install"
    printf '[L3-DISPLAY] dpkg architecture: '
    run_target "$rootfs" dpkg --print-architecture
    printf '[L3-DISPLAY] dpkg foreign architectures: '
    run_target "$rootfs" dpkg --print-foreign-architectures || true
    printf '[L3-DISPLAY] apt architecture/config:\n'
    run_target "$rootfs" apt-config "${apt_options[@]}" dump \
        | grep -E '^(APT::(Architecture|Architectures)|Dir::Etc::(sourcelist|sourceparts)|Acquire::(Check-Valid-Until|By-Hash))' || true
    printf '[L3-DISPLAY] apt preferences (first 120 lines per file):\n'
    run_target "$rootfs" sh -c 'find /etc/apt/preferences /etc/apt/preferences.d -maxdepth 1 -type f -print -exec sed -n "1,120p" {} \\;' 2>/dev/null \
        | sed -E 's#(https?://)[^/@[:space:]]+@#\1REDACTED@#g; s#([Pp]ass(word|wd)|[Tt]oken|[Ss]ecret|[Aa]uthorization)[=:][[:space:]]*[^[:space:]]+#\1=REDACTED#g' \
        | awk 'NR <= 240 { print }' || true
    printf '[L3-DISPLAY] dpkg selections for resolver-relevant packages:\n'
    bounded_target dpkg --get-selections \
        | awk '$1 ~ /(ffmpeg|libav|swresample|mpv|^libc6(:|$)|^libstdc[+][+])/{ print }'
    printf '[L3-DISPLAY] dpkg holds (selection and apt-mark):\n'
    bounded_target dpkg --get-selections | awk '$2 == "hold" { print }'
    bounded_target apt-mark showhold
    printf '[L3-DISPLAY] installed resolver-relevant packages:\n'
    bounded_target dpkg-query -W -f='${Package} ${Version} ${Architecture} ${Status}\\n' \
        | awk '$4 == "installed" && $5 == "ok" && $6 == "installed" && $1 ~ /(ffmpeg|libav|swresample|mpv|^libc6(:|$)|^libstdc[+][+])/{ print }'
    for package in libswresample4 libavcodec59 libavdevice59 libavfilter8 libavformat59 mpv libmpv2 libc6 libstdc++6; do
        printf '[L3-DISPLAY] apt-cache policy %s:\n' "$package"
        bounded_target apt-cache "${apt_options[@]}" policy "$package"
        printf '[L3-DISPLAY] installed %s:\n' "$package"
        bounded_target dpkg-query -W -f='${Package} ${Version} ${Architecture} ${Status}\\n' "$package"
    done
    printf '[L3-DISPLAY] simulated locked install with resolver trace (first 240 lines):\n'
    bounded_target env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" \
        -s -y --no-install-recommends \
        -o Debug::pkgProblemResolver=yes -o Debug::pkgDepCache::Marker=1 install "$@"
}

install_locked_packages() {
    local rootfs="$1" line name version architecture filename sha256
    local -a specs=() lock_names=()
    while IFS=$'\t' read -r name version architecture filename sha256; do
        [[ -n "$name" ]] || continue
        specs+=("$name=$version")
        lock_names+=("$name")
        printf '%s %s (%s)\n' "$name" "$version" "$architecture"
    done < <(load_lock)
    ((${#specs[@]} == 12)) || error "packages.lock must contain exactly 12 display packages"

    prepare_apt_state "$rootfs"
    run_target "$rootfs" env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" update
    diagnose_apt_state "$rootfs" "${specs[@]}"
    run_target "$rootfs" env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" -y --no-install-recommends --download-only install "${specs[@]}"

    while IFS=$'\t' read -r name version architecture filename sha256; do
        [[ -n "$name" ]] || continue
        local deb=""
        deb=$(find "$rootfs/var/cache/apt/archives" -maxdepth 1 -type f -name "$filename" -print -quit)
        [[ -n "$deb" ]] || error "APT did not cache locked archive $filename"
        [[ "$(sha256sum "$deb" | cut -d' ' -f1)" == "$sha256" ]] \
            || error "SHA256 mismatch for locked archive $filename"
    done < <(load_lock)

    run_target "$rootfs" env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" -y --no-install-recommends install "${specs[@]}"
    local i actual arch
    for i in "${!lock_names[@]}"; do
        actual=$(run_target "$rootfs" dpkg-query -W -f='${Version}' "${lock_names[$i]}")
        [[ "$actual" == "${specs[$i]#*=}" ]] || error "Locked version not installed for ${lock_names[$i]}: $actual"
        arch=$(run_target "$rootfs" dpkg-query -W -f='${Architecture}' "${lock_names[$i]}")
        [[ "$arch" == amd64 || "$arch" == all ]] || error "Unexpected architecture for ${lock_names[$i]}: $arch"
    done
}

validate_target_runtime() {
    local rootfs="$1"
    run_target "$rootfs" /bin/sh -c 'command -v cage' >/dev/null \
        || error "cage executable missing from target rootfs"
    run_target "$rootfs" /bin/sh -c 'command -v mpv' >/dev/null \
        || error "mpv executable missing from target rootfs"
    run_target "$rootfs" /bin/sh -c 'command -v python3' >/dev/null \
        || error "python3 executable missing from target rootfs"
    run_target "$rootfs" python3 -c 'import mpv; print(mpv.MPV)' >/dev/null \
        || error "target rootfs Python mpv import/API check failed"
}

install_user_and_service() {
    local rootfs="$1"
    run_target "$rootfs" groupadd --system --force video
    run_target "$rootfs" groupadd --system --force render
    run_target "$rootfs" groupadd --system --force seat
    if ! run_target "$rootfs" getent passwd ashipa >/dev/null; then
        run_target "$rootfs" useradd --create-home --shell /bin/bash --user-group ashipa
    fi
    install -D -m 0755 "$LAYER_DIR/files/usr/libexec/ashipaos-display" "$rootfs/usr/libexec/ashipaos-display"
    install -D -m 0644 "$LAYER_DIR/files/etc/systemd/system/ashipaos-display.service" "$rootfs/etc/systemd/system/ashipaos-display.service"
    mkdir -p "$rootfs/etc/systemd/system/graphical.target.wants"
    ln -sfn ../ashipaos-display.service "$rootfs/etc/systemd/system/graphical.target.wants/ashipaos-display.service"
}

write_evidence() {
    local rootfs="$1" output="$2" pkg version policy
    mkdir -p "$EVIDENCE_DIR"
    {
        printf '{\n  "layer": 3,\n  "target": "x86_64",\n  "verification_class": "BUILD",\n  "debian_suite": "bookworm",\n  "debian_architecture": "amd64",\n  "package_lock": "config/packages.lock",\n  "rootfs_tarball": "%s",\n  "playback_asset": {"path": "/usr/share/ashipaos/display/test-video.mp4", "status": "BLOCKED_UNTIL_REPRODUCIBLE_ASSET"},\n  "packages": {\n' "$output"
        while IFS=$'\t' read -r pkg version architecture filename sha256; do
            [[ -n "$pkg" ]] || continue
            policy=$(run_target "$rootfs" apt-cache "${apt_options[@]}" policy "$pkg" | tr '\n' ' ' | sed 's/"/\\"/g')
            printf '    "%s": {"version": "%s", "architecture": "%s", "sha256": "%s", "apt_policy": "%s"}%s\n' \
                "$pkg" "$version" "$architecture" "$sha256" "$policy" "$([[ "$pkg" == python3-mpv ]] && echo '' || echo ',')"
        done < <(load_lock)
        printf '  },\n  "service": "ashipaos-display.service",\n  "runtime_user": "ashipa",\n  "physical_gpu_gate": "HARDWARE"\n}\n'
    } > "$EVIDENCE_DIR/build-evidence.json"
}

main() {
    [[ $# -eq 2 ]] || { usage; exit 2; }
    local input="$1" target="$2" output
    [[ "$target" == x86_64 ]] || error "Layer 3 display is x86_64-only; refusing target '$target'"
    [[ -s "$input" ]] || error "Rootfs tarball not found or empty: $input"
    [[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
    command -v mount >/dev/null 2>&1 || error "mount is required"

    TEMP_DIR=$(mktemp -d)
    ROOTFS="$TEMP_DIR/rootfs"
    trap 'cleanup; [[ -n "${TEMP_DIR:-}" ]] && rm -rf -- "$TEMP_DIR"' EXIT
    mkdir -p "$ROOTFS"
    tar -xzf "$input" -C "$ROOTFS" \
        --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*'
    mount_api "$ROOTFS"

    mkdir -p "$ROOTFS/etc/apt/sources.list.d"
    lock_source_line > "$ROOTFS$SOURCE_LIST"
    printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
    chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"
    log "Installing exact Layer 3 package lock from Debian Bookworm snapshot"
    install_locked_packages "$ROOTFS"
    rm -f "$ROOTFS/usr/sbin/policy-rc.d"
    validate_target_runtime "$ROOTFS"
    install_user_and_service "$ROOTFS"
    output="${input}.display.tmp"
    write_evidence "$ROOTFS" "$input"
    cleanup
    tar -C "$ROOTFS" \
        --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*' \
        -czf "$output" .
    mv -f "$output" "$input"
    log "Installed display contract into $input"
}

main "$@"
