#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer5-application"
SCRIPT="$LAYER/scripts/build-application.sh"
LAUNCHER="$LAYER/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
CONFIG="$LAYER/config/application-config.yaml"
LOCK="$LAYER/config/dependencies.lock.json"
EVIDENCE="$LAYER/evidence/build-evidence.json"
[[ -x "$SCRIPT" && -x "$LAUNCHER" ]]
[[ -f "$CONFIG" && -f "$LOCK" && -f "$EVIDENCE" ]]
[[ ! -e "$LAYER/files/etc/systemd/system/jellyfin-mpv-shim.service" ]]
grep -q '^#!/usr/bin/env bash$' "$SCRIPT" "$LAUNCHER"
grep -q 'tomllib' "$SCRIPT"
grep -q 'build-system' "$SCRIPT"
grep -qi 'metadata-only' "$SCRIPT"
grep -q 'rootfs_output_owner' "$SCRIPT"
grep -q 'REPO_ROOT="$(cd "$LAYER_DIR/../.." && pwd)"' "$SCRIPT"
grep -q 'source "$REPO_ROOT/scripts/rootfs-ownership.sh"' "$SCRIPT"
grep -q 'active metadata ownership' "$LAUNCHER"
grep -q 'manifest_mode' "$LAUNCHER"
grep -q 'slot directory ownership' "$LAUNCHER"
grep -q 'configuration ownership' "$LAUNCHER"
grep -q 'sha256sum' "$LAUNCHER"
grep -q 'dependency_status.*RESOLVED' "$LAUNCHER"
grep -q 'value\["version"\]' "$LAUNCHER"
grep -q 'no validated executable bundle' "$LAUNCHER"
grep -q 'UNRESOLVED' "$LOCK"
grep -q 'BLOCKED_UNTIL_EXACT_TARGET_LOCK' "$CONFIG" "$LOCK" "$SCRIPT"
grep -q 'python-mpv>=1.0.8' "$CONFIG" "$LOCK"
grep -q 'jellyfin-apiclient-python>=1.18.0' "$CONFIG" "$LOCK"
grep -q 'python-mpv-jsonipc>=1.4.0' "$CONFIG" "$LOCK"
! grep -q 'python3-mpv' "$CONFIG" "$SCRIPT"
grep -q 'forbidden_debian_package.*python3-mpv' "$LOCK"
! grep -qE 'idle=yes|test-video|/usr/bin/mpv|chown .*|| true' "$LAUNCHER" "$SCRIPT"
python3 - "$CONFIG" "$LOCK" "$EVIDENCE" <<'PY'
import json, sys
lock=json.load(open(sys.argv[2],encoding='utf-8'))
evidence=json.load(open(sys.argv[3],encoding='utf-8'))
assert lock['status']=='UNRESOLVED'
assert lock['forbidden_debian_package']=='python3-mpv'
assert lock['resolution']['must_record']==['name','version','sha256','filename','python_tag','abi_tag','platform_tag']
assert evidence['artifact_mode']=='METADATA_ONLY'
assert evidence['runnable_bundle']=='NOT_CREATED'
PY
bash "$LAYER/tests/mutation-tests.sh"
printf 'layer5-application-static: PASS\n'
