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
[[ ${#v[@]} -eq 8 ]] || { echo "CE-2A pin validation failed: $PIN" >&2; exit 1; }
commit=${v[0]}; archive_sha=${v[1]}; docker_sha=${v[2]}; base_digest=${v[3]}; archive_url=${v[4]}; artifact_rel=${v[5]}; dockerfile_rel=${v[6]}; base_ref=${v[7]}
exec > >(tee "$EVIDENCE/ce2a-build.log") 2>&1
printf '%s\n' "CE-2A pinned source build" "commit=$commit" "archive_sha256=$archive_sha" "base=$base_ref"
archive="$WORKSPACE/source.tar.gz"
curl --fail --location --retry 3 --output "$archive" "$archive_url"
echo "$archive_sha  $archive" | sha256sum --check --status
rm -rf "$WORKSPACE/source"; mkdir -p "$WORKSPACE/source"
tar --extract --gzip --file "$archive" --strip-components=1 --directory "$WORKSPACE/source"
# CI-only pax-utils source override: the Gentoo distfile is byte-equivalent to
# the v1.3.7 GitHub source tree used by the package, including all build files.
pax_pkg="$WORKSPACE/source/packages/devel/pax-utils/package.mk"
pax_url='https://dev.gentoo.org/~sam/distfiles/app-misc/pax-utils/pax-utils-1.3.7.tar.xz'
pax_sha='108362d29668d25cf7b0cadc63b15a4c1cfc0dbc71adc151b33c5fe7dece939'
export pax_pkg pax_url pax_sha
python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ['pax_pkg'])
text = path.read_text(encoding='utf-8')
old_sha = 'PKG_SHA256="907fdcfc6c6c2913a8e42847f8096027b0a953b9344208d14daf2324fd711638"'
old_url = 'PKG_URL="https://gitweb.gentoo.org/proj/pax-utils.git/snapshot/pax-utils-${PKG_VERSION}.tar.bz2"'
new_sha = f'PKG_SHA256="{os.environ["pax_sha"]}"'
new_url = f'PKG_URL="{os.environ["pax_url"]}"'
assert text.count(old_sha) == 1 and text.count(old_url) == 1
assert text.count('PKG_VERSION="1.3.7"') == 1
assert text.count('PKG_DEPENDS_HOST="toolchain:host"') == 1
assert text.count('PKG_MESON_OPTS_HOST="-Duse_libcap=disabled"') == 1
updated = text.replace(old_sha, new_sha).replace(old_url, new_url)
assert updated.count('PKG_SHA256=') == 1 and updated.count('PKG_URL=') == 1
path.write_text(updated, encoding='utf-8')
PY
pax_override_content=$'PKG_SHA256="'$pax_sha'"\nPKG_URL="'$pax_url'"'
pax_override_sha256=$(printf '%s\n' "$pax_override_content" | sha256sum | cut -d' ' -f1)
curl --fail --location --retry 3 --output "$WORKSPACE/pax-utils-1.3.7.tar.xz" "$pax_url"
printf '%s  %s\n' "$pax_sha" "$WORKSPACE/pax-utils-1.3.7.tar.xz" | sha256sum --check --status
printf '%s\n' "$pax_override_content" "sha256=$pax_override_sha256" > "$EVIDENCE/pax-utils-override.txt"
printf '%s\n' "distfile_url=$pax_url" "distfile_sha256=$pax_sha" "override_sha256=$pax_override_sha256" > "$EVIDENCE/pax-utils-distfile.txt"
mirror_options_content='DISTRO_MIRROR="https://ftp.gnu.org/gnu http://sources.coreelec.org http://sources.libreelec.tv/mirror"'
mkdir -p "$WORKSPACE/source/.coreelec"
printf '%s\n' "$mirror_options_content" > "$WORKSPACE/source/.coreelec/options"
mirror_options_sha256=$(sha256sum "$WORKSPACE/source/.coreelec/options" | cut -d' ' -f1)
[[ "$(sha256sum "$WORKSPACE/source/$dockerfile_rel" | cut -d' ' -f1)" == "$docker_sha" ]] || { echo 'Dockerfile hash mismatch' >&2; exit 1; }
# The pinned Dockerfile hard-codes `FROM ubuntu:jammy`. Pull the pinned digest,
# verify it, and tag it locally as ubuntu:jammy so the no-pull build can only
# use the pinned base; no host build path is accepted.
docker pull --platform linux/amd64 "$base_ref"
docker image inspect --format '{{join .RepoDigests "\n"}}' "$base_ref" | grep -Fxq "ubuntu@$base_digest" \
  || { echo "pulled base image does not carry the pinned digest $base_digest" >&2; exit 1; }
docker tag "$base_ref" ubuntu:jammy
image="ce2a-builder:${commit:0:12}"
docker build --pull=false --tag "$image" --file "$WORKSPACE/source/$dockerfile_rel" "$WORKSPACE/source"
chmod -R a+rwX "$WORKSPACE/source"
docker run --rm --init --user docker -w /build -e PROJECT=Amlogic-ce -e DEVICE=Amlogic-ng -e ARCH=arm -e OFFICIAL=yes -e CUSTOM_GIT_HASH="$commit" -v "$WORKSPACE/source:/build" "$image" bash -lc 'PROJECT=Amlogic-ce DEVICE=Amlogic-ng ARCH=arm OFFICIAL=yes make image'
# Make the runner-readable
# output explicit before host-side inspection and evidence collection.
chmod -R a+rX "$WORKSPACE/source/target"
count=$(find "$WORKSPACE/source/target" -maxdepth 1 -type f -name 'CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz' -print | wc -l)
[[ "$count" -eq 1 ]] || { echo "expected exactly one Generic artifact, got $count" >&2; exit 1; }
artifact="$WORKSPACE/source/$artifact_rel"; chmod a+r "$artifact"; sha256sum "$artifact" | tee "$EVIDENCE/artifact.sha256"
printf '%s\n' "artifact=$artifact_rel" "artifact_count=$count" "base_digest=$base_digest" "mirror_options_content=$mirror_options_content" "mirror_options_sha256=$mirror_options_sha256" > "$EVIDENCE/ce2a-build-result.txt"
printf '%s\n' "$mirror_options_content" "sha256=$mirror_options_sha256" > "$EVIDENCE/ce2a-mirror-override.txt"
cp "$artifact" "$EVIDENCE/"
