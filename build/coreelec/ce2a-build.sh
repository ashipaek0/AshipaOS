#!/usr/bin/env bash
# CE-2A: CI-only, immutable CoreELEC source build. Never run locally.
set -Eeuo pipefail
usage() { echo "Usage: $0 [--ci] PIN WORKSPACE EVIDENCE_DIR" >&2; exit 64; }
ci=false
if [[ "${1:-}" == "--ci" ]]; then ci=true; shift; fi
$ci || { echo "CE-2A BUILD is blocked outside GitHub Actions; pass --ci explicitly in CI" >&2; exit 78; }
[[ "${CI:-}" == true ]] || { echo "CE-2A BUILD requires CI=true" >&2; exit 78; }
[[ $# -eq 3 ]] || usage
PIN=$(realpath "$1")
mkdir -p "$2" "$3"
WORKSPACE=$(realpath "$2"); EVIDENCE=$(realpath "$3")
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export PIN WORKSPACE EVIDENCE ROOT
mapfile -t v < <(python3 - <<'PY'
import json, os, re
p=json.load(open(os.environ['PIN'],encoding='utf8')); s=p['source']; b=p['builder']; base=b['base_image']; t=p['build']; a=p['artifact']
assert s['repository']=='https://github.com/ashipaek0/CoreELEC.git' and s['fork']=={'full_name':'ashipaek0/CoreELEC','required':True,'parent':'CoreELEC/CoreELEC'}
assert s['upstream_repository']=='https://github.com/CoreELEC/CoreELEC.git' and s['upstream_source_line']=='coreelec-21'
assert s['ref']=={'type':'tag','value':'21.3-Omega'} and re.fullmatch(r'[0-9a-f]{40}',s['commit']) and s['commit']==s['fork_commit']==s['upstream_commit']
assert re.fullmatch(r'[0-9a-f]{64}',s['archive']['sha256'])
assert b['dockerfile']['path']=='tools/docker/jammy/Dockerfile' and re.fullmatch(r'[0-9a-f]{64}',b['dockerfile']['sha256'])
assert base['tag']=='ubuntu:jammy' and re.fullmatch(r'sha256:[0-9a-f]{64}',base['digest']) and base['pinned_reference']=='ubuntu@'+base['digest']
assert t=={'PROJECT':'Amlogic-ce','DEVICE':'Amlogic-ng','ARCH':'arm','OFFICIAL':'yes'}
assert a=={'path':'target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz','name':'CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz','glob':'target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz'}
for x in (s['commit'],s['archive']['sha256'],b['dockerfile']['sha256'],base['digest']): print(x)
print(s['archive']['url']); print(a['path']); print(b['dockerfile']['path']); print(base['pinned_reference'])
PY
)
commit=${v[0]}; archive_sha=${v[1]}; docker_sha=${v[2]}; base_digest=${v[3]}; archive_url=${v[4]}; artifact_rel=${v[5]}; dockerfile_rel=${v[6]}; base_ref=${v[7]}
exec > >(tee "$EVIDENCE/ce2a-build.log") 2>&1
printf '%s\n' "CE-2A pinned source build" "commit=$commit" "archive_sha256=$archive_sha" "base=$base_ref"
archive="$WORKSPACE/source.tar.gz"
curl --fail --location --retry 3 --output "$archive" "$archive_url"
echo "$archive_sha  $archive" | sha256sum --check --status
rm -rf "$WORKSPACE/source"; mkdir -p "$WORKSPACE/source"
tar --extract --gzip --file "$archive" --strip-components=1 --directory "$WORKSPACE/source"
[[ "$(sha256sum "$WORKSPACE/source/$dockerfile_rel" | cut -d' ' -f1)" == "$docker_sha" ]] || { echo 'Dockerfile hash mismatch' >&2; exit 1; }
grep -Fxq 'PROJECT=Amlogic-ce' "$WORKSPACE/source/.config" 2>/dev/null || true
# The Dockerfile is rebuilt with the exact pinned base; no host build path is accepted.
image="ce2a-builder:${commit:0:12}"
docker build --pull=false --build-arg "BASE_IMAGE=$base_ref" --tag "$image" --file "$WORKSPACE/source/$dockerfile_rel" "$WORKSPACE/source"
chmod -R a+rwX "$WORKSPACE/source"
docker run --rm --init --user docker -w /build -e PROJECT=Amlogic-ce -e DEVICE=Amlogic-ng -e ARCH=arm -e OFFICIAL=yes -e CUSTOM_GIT_HASH="$commit" -v "$WORKSPACE/source:/build" "$image" bash -lc 'PROJECT=Amlogic-ce DEVICE=Amlogic-ng ARCH=arm OFFICIAL=yes make image'
# Make the runner-readable
# output explicit before host-side inspection and evidence collection.
chmod -R a+rX "$WORKSPACE/source/target"
count=$(find "$WORKSPACE/source/target" -maxdepth 1 -type f -name 'CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz' -print | wc -l)
[[ "$count" -eq 1 ]] || { echo "expected exactly one Generic artifact, got $count" >&2; exit 1; }
artifact="$WORKSPACE/source/$artifact_rel"; chmod a+r "$artifact"; sha256sum "$artifact" | tee "$EVIDENCE/artifact.sha256"
printf '%s\n' "artifact=$artifact_rel" "artifact_count=$count" "base_digest=$base_digest" > "$EVIDENCE/ce2a-build-result.txt"
cp "$artifact" "$EVIDENCE/"
