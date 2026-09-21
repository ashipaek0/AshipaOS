#!/usr/bin/env bash
set -Eeuo pipefail
# Layer 5: reproducible Jellyfin MPV Shim application bundle.
# The resolver supplies exact target wheels and native ABI evidence.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"
CONFIG="$LAYER_DIR/config/application-config.yaml"
SOURCE_URL="https://github.com/jellyfin/jellyfin-mpv-shim/archive/9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315.tar.gz"
SOURCE_SHA256="c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731"
VERSION="3.0.0"
INPUT="${1:-}"
TARGET="${2:-}"
RESOLUTION="${3:-}"
error() { printf '[L5-APPLICATION ERROR] %s\n' "$*" >&2; exit 1; }
[[ $# -eq 3 ]] || { printf 'Usage: %s <rootfs-tar.gz> <x86_64|a95x-f3-air> <resolution.json>\n' "$(basename "$0")"; exit 2; }
[[ "$TARGET" == x86_64 || "$TARGET" == a95x-f3-air ]] || error "unsupported target: $TARGET"
[[ -s "$INPUT" && -s "$RESOLUTION" && -f "$CONFIG" ]] || error "application inputs are incomplete"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ashipaos-application.XXXXXX")
cleanup() { rm -rf -- "$TMP"; return 0; }
trap cleanup EXIT
ARCHIVE="$TMP/source.tar.gz"
python3 - "$ARCHIVE" "$SOURCE_URL" "$SOURCE_SHA256" <<'PY'
import hashlib, pathlib, sys, urllib.request
out, url, expected = sys.argv[1:]
with urllib.request.urlopen(url, timeout=120) as response, open(out, 'wb') as handle:
    while chunk := response.read(1024 * 1024): handle.write(chunk)
actual = hashlib.sha256(pathlib.Path(out).read_bytes()).hexdigest()
if actual != expected: raise SystemExit(f'source archive SHA-256 mismatch: {actual} != {expected}')
PY

ROOTFS_DIR="$TMP/rootfs"
mkdir -p "$ROOTFS_DIR"
tar -xzf "$INPUT" -C "$ROOTFS_DIR" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*'

python3 - "$RESOLUTION" "$TMP" "$ROOTFS_DIR" "$ARCHIVE" "$TARGET" <<'PY'
import hashlib, json, pathlib, shutil, sys, urllib.request, zipfile
resolution, tmp, rootfs, archive, target = map(pathlib.Path, sys.argv[1:5])
target_name = sys.argv[5]
data = json.loads(resolution.read_text(encoding='utf-8'))
if data.get('status') != 'RESOLVED': raise SystemExit('dependency resolution is not RESOLVED')
items = data.get('artifacts')
if not isinstance(items, list) or not items: raise SystemExit('resolved artifact list is empty')
wheel_dir = pathlib.Path(tmp) / 'wheels'; wheel_dir.mkdir()
for item in items:
    url, expected, filename = item.get('url'), item.get('sha256'), item.get('filename')
    if not isinstance(url, str) or not url.startswith('https://') or not isinstance(expected, str) or len(expected) != 64 or not isinstance(filename, str) or not filename.endswith('.whl'):
        raise SystemExit('resolved artifact lacks verified URL/hash/filename')
    destination = wheel_dir / filename
    with urllib.request.urlopen(url, timeout=120) as response, destination.open('wb') as out: shutil.copyfileobj(response, out)
    actual = hashlib.sha256(destination.read_bytes()).hexdigest()
    if actual != expected: raise SystemExit(f'artifact SHA-256 mismatch: {filename}')
site = rootfs / 'usr/lib/python3/dist-packages'; site.mkdir(parents=True, exist_ok=True)
for wheel in sorted(wheel_dir.glob('*.whl')):
    with zipfile.ZipFile(wheel) as archive_zip: archive_zip.extractall(site)
source_dst = rootfs / 'usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0/source.tar.gz'
source_dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(archive, source_dst)
(source_dst.parent / 'dependency-resolution.json').write_text(json.dumps(data, indent=2, sort_keys=True) + '\n', encoding='utf-8')
lock = {'schema':'ashipaos.jellyfin-mpv-shim.dependency-lock.v1','status':'RESOLVED','target':data.get('target',{}),'artifacts':items}
(source_dst.parent / 'dependencies.lock.json').write_text(json.dumps(lock, indent=2, sort_keys=True) + '\n', encoding='utf-8')
(source_dst.parent / 'dependency-sbom.json').write_text(json.dumps({'bomFormat':'CycloneDX','specVersion':'1.5','metadata':{'component':{'name':'jellyfin-mpv-shim','version':'3.0.0'}},'components':[{'type':'library','name':i['name'],'version':i['version'],'hashes':[{'alg':'SHA-256','content':i['sha256']}]} for i in items]}, indent=2) + '\n', encoding='utf-8')
slot = source_dst.parent / 'bin'; slot.mkdir(parents=True, exist_ok=True)
entry = """#!/bin/sh
exec /usr/bin/python3 -c 'from jellyfin_mpv_shim.mpv_shim import main; main()' "$@"
"""
exe = slot / 'jellyfin-mpv-shim'; exe.write_text(entry, encoding='utf-8'); exe.chmod(0o755)
manifest = {'schema':'ashipaos.jellyfin-mpv-shim.slot.v1','name':'jellyfin-mpv-shim','version':'3.0.0','executable':'bin/jellyfin-mpv-shim','sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'python_tag':data['target']['python_tag'],'abi_tag':data['target']['abi_tag'],'platform_tag':data['target']['platform_tag'],'dependency_status':'RESOLVED'}
(source_dst.parent / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
PY

install -D -m 0755 "$LAYER_DIR/files/usr/libexec/ashipaos-jellyfin-mpv-shim" "$ROOTFS_DIR/usr/libexec/ashipaos-jellyfin-mpv-shim"
mkdir -p "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim/slots"
uid=$(awk -F: '$1 == "ashipa" {print $3; exit}' "$ROOTFS_DIR/etc/passwd")
gid=$(awk -F: '$1 == "ashipa" {print $3; exit}' "$ROOTFS_DIR/etc/group")
[[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || error "target rootfs lacks ashipa ownership identity"
chown -R "$uid:$gid" "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim"
chmod 0700 "$ROOTFS_DIR/storage/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim" "$ROOTFS_DIR/storage/apps/jellyfin-mpv-shim/slots"

OUT="$TMP/rootfs.tar.gz"
tar -C "$ROOTFS_DIR" --exclude='./dev/*' --exclude='dev/*' --exclude='./proc/*' --exclude='proc/*' --exclude='./sys/*' --exclude='sys/*' --exclude='./run/*' --exclude='run/*' -czf "$OUT" .
mv -f "$OUT" "$INPUT"
rootfs_output_owner "$INPUT" "$(dirname "$INPUT")"
printf 'layer5-application: RESOLVED runnable bundle staged for %s\n' "$TARGET"
