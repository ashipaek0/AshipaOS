#!/usr/bin/env bash
set -Eeuo pipefail
# Layer 5 application metadata staging. x86_64 only. The unresolved wheel
# closure deliberately prevents creation of a runnable application bundle.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$LAYER_DIR/config/application-config.yaml"
LOCK="$LAYER_DIR/config/dependencies.lock.json"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/rootfs-ownership.sh"
ARCHIVE_URL="https://github.com/jellyfin/jellyfin-mpv-shim/archive/9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315.tar.gz"
ARCHIVE_SHA256="c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731"
VERSION=3.0.0
TARGET="${2:-}"
INPUT="${1:-}"
error() { printf '[L5-APPLICATION ERROR] %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s <rootfs-tar.gz> x86_64\n' "$(basename "$0")"; }
[[ $# -eq 2 ]] || { usage; exit 2; }
[[ "$TARGET" == x86_64 ]] || error "Layer 5 application is x86_64-only; refusing target '$TARGET'"
[[ -s "$INPUT" ]] || error "rootfs tarball not found or empty: $INPUT"
[[ -f "$CONFIG" && -f "$LOCK" ]] || error "application metadata is incomplete"
command -v python3 >/dev/null || error "python3 is required for metadata extraction"

TMP=$(mktemp -d)
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
ARCHIVE="$TMP/source.tar.gz"
python3 - "$ARCHIVE" "$ARCHIVE_URL" "$ARCHIVE_SHA256" <<'PY'
import hashlib, pathlib, sys, urllib.request
out, url, expected = sys.argv[1:]
with urllib.request.urlopen(url, timeout=120) as response, open(out, "wb") as handle:
    while chunk := response.read(1024 * 1024):
        handle.write(chunk)
digest = hashlib.sha256(pathlib.Path(out).read_bytes()).hexdigest()
if digest != expected:
    raise SystemExit(f"source archive SHA-256 mismatch: {digest} != {expected}")
PY
mkdir -p "$TMP/src"
tar -xzf "$ARCHIVE" -C "$TMP/src" --strip-components=1
python3 - "$TMP/src/pyproject.toml" "$TMP/dependency-sbom.json" "$LOCK" <<'PY'
import hashlib, json, pathlib, sys, tomllib
pyproject, sbom, lock = map(pathlib.Path, sys.argv[1:])
data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
project = data.get("project", {})
build = data.get("build-system", {})
requirements = project.get("dependencies", [])
required = [
    "python-mpv>=1.0.8",
    "jellyfin-apiclient-python>=1.18.0",
    "python-mpv-jsonipc>=1.4.0",
    "requests",
    "pillow",
]
if requirements != required:
    raise SystemExit(f"upstream mandatory dependencies differ: {requirements!r}")
if build.get("requires") != ["setuptools>=77", "wheel"]:
    raise SystemExit(f"upstream build requirements differ: {build.get('requires')!r}")
if project.get("requires-python") != ">=3.9":
    raise SystemExit("upstream Python requirement differs")
if project.get("scripts", {}).get("jellyfin-mpv-shim") != "jellyfin_mpv_shim.mpv_shim:main":
    raise SystemExit("upstream entry point missing or changed")
if "python3-mpv" in pyproject.read_text(encoding="utf-8"):
    raise SystemExit("incompatible Debian python3-mpv must never enter the application closure")
lock_data = json.loads(lock.read_text(encoding="utf-8"))
if lock_data.get("status") != "UNRESOLVED":
    raise SystemExit("dependency lock status unexpectedly changed")
source_sha = hashlib.sha256(pyproject.read_bytes()).hexdigest()
sbom_data = {
    "bomFormat": "CycloneDX", "specVersion": "1.5",
    "metadata": {"component": {"name": "jellyfin-mpv-shim", "version": "3.0.0", "commit": "9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315"}},
    "components": [{"type": "library", "name": item.split(">=", 1)[0], "version": "UNRESOLVED", "scope": "required"} for item in required],
    "resolution_status": "BLOCKED_UNTIL_EXACT_TARGET_LOCK",
    "build_requirements": ["setuptools>=77", "wheel"],
    "upstream_pyproject_sha256": source_sha,
}
pathlib.Path(sbom).write_text(json.dumps(sbom_data, indent=2) + "\n", encoding="utf-8")
PY

ROOTFS_DIR="$TMP/rootfs"
mkdir -p "$ROOTFS_DIR"
tar -xzf "$INPUT" -C "$ROOTFS_DIR" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*'
# Metadata-only staging: no bin/launcher is installed while the lock is unresolved.
install -D -m 0755 "$LAYER_DIR/files/usr/libexec/ashipaos-jellyfin-mpv-shim" "$ROOTFS_DIR/usr/libexec/ashipaos-jellyfin-mpv-shim"
mkdir -p "$ROOTFS_DIR/usr/lib/ashipaos/apps/jellyfin-mpv-shim/$VERSION" "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim/slots"
cp "$ARCHIVE" "$ROOTFS_DIR/usr/lib/ashipaos/apps/jellyfin-mpv-shim/$VERSION/source.tar.gz"
cp "$TMP/dependency-sbom.json" "$ROOTFS_DIR/usr/lib/ashipaos/apps/jellyfin-mpv-shim/$VERSION/dependency-sbom.json"
cp "$LOCK" "$ROOTFS_DIR/usr/lib/ashipaos/apps/jellyfin-mpv-shim/$VERSION/dependencies.lock.json"

# Resolve ownership from the target rootfs, never from the build host. Missing
# target identities are an error; silently leaving root ownership is unsafe.
ashipa_uid=$(awk -F: '$1 == "ashipa" {print $3; exit}' "$ROOTFS_DIR/etc/passwd")
ashipa_gid=$(awk -F: '$1 == "ashipa" {print $3; exit}' "$ROOTFS_DIR/etc/group")
[[ "$ashipa_uid" =~ ^[0-9]+$ && "$ashipa_gid" =~ ^[0-9]+$ ]] || error "target rootfs lacks ashipa ownership identity"
chown -R "$ashipa_uid:$ashipa_gid" "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim"
chmod 0700 "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim/slots"

OUT="$TMP/rootfs.tar.gz"
tar -C "$ROOTFS_DIR" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' -czf "$OUT" .
mv -f "$OUT" "$INPUT"
rootfs_output_owner "$INPUT" "$(dirname "$INPUT")"
printf 'layer5-application: metadata staged; runnable bundle blocked by unresolved exact dependency closure\n'
