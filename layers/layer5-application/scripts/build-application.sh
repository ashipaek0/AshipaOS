#!/usr/bin/env bash
# Layer 5: install the Jellyfin MPV Shim bundle into the Layer 1 rootfs.
# Verification Class: BUILD (CI only; consumes the hash-verified output of
# `jellyfin-bundle.py resolve` and performs no network access)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
BUNDLE_TOOL="$SCRIPT_DIR/jellyfin-bundle.py"
LOCK="$LAYER_DIR/config/dependencies.lock.json"
LAUNCHER="$LAYER_DIR/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
APP_NAME="jellyfin-mpv-shim"
APP_VERSION="3.0.0"
BUNDLE_REL="usr/lib/ashipaos/apps/$APP_NAME/$APP_VERSION"
SERVICE_USER="ashipa"
SERVICE="ashipaos-jellyfin-mpv-shim.service"

usage() { printf 'Usage: %s <rootfs.tar.gz> a95x-f3-air <resolution.json> <artifacts-dir>\n' "$(basename "$0")"; }
error() { printf '[L5-APPLICATION ERROR] %s\n' "$*" >&2; exit 1; }

if [[ $# -ne 4 ]]; then
    usage >&2
    exit 2
fi
INPUT="$1" TARGET="$2" RESOLUTION="$3" ARTIFACTS="$4"
[[ "$TARGET" == a95x-f3-air ]] || error "unsupported target: $TARGET"
[[ -s "$INPUT" && -s "$RESOLUTION" && -d "$ARTIFACTS" && -f "$LOCK" ]] || error "application inputs are incomplete"

# Root is required to keep the rootfs ownership intact across the repack.
if [[ $EUID -ne 0 ]]; then
    exec sudo bash "${BASH_SOURCE[0]}" "$@"
fi
# shellcheck source=scripts/rootfs-ownership.sh
source "$REPO_ROOT/scripts/rootfs-ownership.sh"

TMP="$(mktemp -d)"
trap 'rm -rf --one-file-system -- "$TMP"' EXIT
ROOTFS="$TMP/rootfs"
BUNDLE="$ROOTFS/$BUNDLE_REL"
mkdir -p "$ROOTFS"
tar -C "$ROOTFS" --numeric-owner --xattrs --acls -xpzf "$INPUT"
[[ ! -e "$BUNDLE" ]] || error "rootfs already contains $BUNDLE_REL"

mkdir -p "$BUNDLE/bin"
python3 "$BUNDLE_TOOL" --lock "$LOCK" install \
    --resolution "$RESOLUTION" --artifacts-dir "$ARTIFACTS" --site "$BUNDLE/site-packages"
install -m 0644 "$ARTIFACTS/source.tar.gz" "$BUNDLE/source.tar.gz"
install -m 0644 "$LOCK" "$BUNDLE/dependencies.lock.json"
install -m 0644 "$RESOLUTION" "$BUNDLE/dependency-resolution.json"

cat >"$BUNDLE/bin/$APP_NAME" <<'EOF'
#!/bin/sh
# Runs the bundled Jellyfin MPV Shim on the target interpreter and libmpv.
bundle=$(dirname "$(dirname "$(readlink -f "$0")")")
PYTHONPATH="$bundle/site-packages" exec /usr/bin/python3 -s -c \
    'from jellyfin_mpv_shim.mpv_shim import main; main()' "$@"
EOF

python3 - "$LOCK" "$BUNDLE" "$APP_NAME" "$APP_VERSION" <<'PY'
import hashlib, json, pathlib, sys
lock_path, bundle, name, version = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
lock = json.loads(pathlib.Path(lock_path).read_text(encoding="utf-8"))
target = lock["target"]
executable = bundle / "bin" / name
sbom = {
    "bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
    "metadata": {"component": {"type": "application", "name": name, "version": version,
                               "purl": f"pkg:github/jellyfin/jellyfin-mpv-shim@{lock['source']['commit']}",
                               "hashes": [{"alg": "SHA-256", "content": lock["source"]["sha256"]}]}},
    "components": [{"type": "library", "name": a["name"], "version": a["version"],
                    "purl": f"pkg:pypi/{a['name'].lower()}@{a['version']}",
                    "hashes": [{"alg": "SHA-256", "content": a["sha256"]}]} for a in lock["artifacts"]],
}
(bundle / "dependency-sbom.json").write_text(json.dumps(sbom, indent=2) + "\n", encoding="utf-8")
# Exactly the field set the launcher validates.
manifest = {"schema": "ashipaos.jellyfin-mpv-shim.slot.v1", "name": name, "version": version,
            "executable": f"bin/{name}", "sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
            "python_tag": target["python_tag"], "abi_tag": target["abi_tag"],
            "platform_tag": target["platform_tag"], "dependency_status": "RESOLVED"}
(bundle / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

# The immutable bundle is root-owned and read-only to everyone else; the
# launcher refuses it otherwise.
chown -R 0:0 "$BUNDLE"
find "$BUNDLE" -type d -exec chmod 0755 {} +
find "$BUNDLE" -type f -exec chmod 0644 {} +
chmod 0755 "$BUNDLE/bin/$APP_NAME"
install -D -m 0755 -o 0 -g 0 "$LAUNCHER" "$ROOTFS/usr/libexec/ashipaos-jellyfin-mpv-shim"

# Boot straight into the shim: the unit is enabled for multi-user.target and
# owns tty1, so the login prompt there is masked. First-boot defaults are
# seeded into /storage by the launcher.
FILES="$LAYER_DIR/files"
install -D -m 0644 -o 0 -g 0 "$FILES/etc/systemd/system/$SERVICE" "$ROOTFS/etc/systemd/system/$SERVICE"
for default in conf.json mpv.conf; do
    install -D -m 0644 -o 0 -g 0 "$FILES/usr/share/ashipaos/$APP_NAME/$default" \
        "$ROOTFS/usr/share/ashipaos/$APP_NAME/$default"
done
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sfn "../$SERVICE" "$ROOTFS/etc/systemd/system/multi-user.target.wants/$SERVICE"
ln -sfn /dev/null "$ROOTFS/etc/systemd/system/getty@tty1.service"
for group in video render audio input; do
    grep -q "^$group:" "$ROOTFS/etc/group" || error "target rootfs lacks the $group group required by $SERVICE"
done

# Writable state lives under /storage and belongs to the service user.
uid="$(awk -F: -v u="$SERVICE_USER" '$1 == u {print $3; exit}' "$ROOTFS/etc/passwd")"
gid="$(awk -F: -v u="$SERVICE_USER" '$1 == u {print $3; exit}' "$ROOTFS/etc/group")"
[[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || error "target rootfs lacks the $SERVICE_USER identity"
install -d -m 0755 -o 0 -g 0 "$ROOTFS/storage" "$ROOTFS/storage/apps"
install -d -m 0700 -o "$uid" -g "$gid" "$ROOTFS/storage/$APP_NAME" \
    "$ROOTFS/storage/apps/$APP_NAME" "$ROOTFS/storage/apps/$APP_NAME/slots"

partial="$INPUT.partial"
tar -C "$ROOTFS" --numeric-owner --xattrs --acls -czf "$partial" .
mv -f -- "$partial" "$INPUT"
rootfs_output_owner "$INPUT" || error "could not restore rootfs ownership"
printf 'layer5-application: bundle %s %s installed for %s\n' "$APP_NAME" "$APP_VERSION" "$TARGET"
