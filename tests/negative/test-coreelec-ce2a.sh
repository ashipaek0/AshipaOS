#!/usr/bin/env bash
# CE-2A negative gates: mutations must fail closed; no image build is performed.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); PIN=$ROOT/build/coreelec/pin.json
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 - "$PIN" "$TMP" <<'PY'
import json, pathlib, sys
p=json.load(open(sys.argv[1])); out=pathlib.Path(sys.argv[2])
mutations={'wrong-fork':(('source','fork','full_name'),'other/CoreELEC'),'wrong-tag':(('source','ref','value'),'main'),'wrong-commit':(('source','commit'),'0'*40),'wrong-archive-hash':(('source','archive','sha256'),'0'*64),'wrong-dockerfile-hash':(('builder','dockerfile','sha256'),'0'*64),'wrong-base-digest':(('builder','base_image','digest'),'sha256:'+'0'*64),'wrong-project':(('build','PROJECT'),'Wrong'),'wrong-device':(('build','DEVICE'),'Wrong'),'wrong-arch':(('build','ARCH'),'arm64'),'wrong-official':(('build','OFFICIAL'),'no'),'wrong-artifact':(('artifact','path'),'target/wrong.img.gz')}
for name,(path,value) in mutations.items():
 q=json.loads(json.dumps(p)); d=q
 for k in path[:-1]: d=d[k]
 d[path[-1]]=value
 (out/(name+'.json')).write_text(json.dumps(q),encoding='utf8')
PY
# Every mutated pin must be rejected by the real build entry point before any
# download (pin validation runs first; CI=true only lifts the local-run block).
for mutated in "$TMP"/wrong-*.json; do
  if CI=true bash "$ROOT/build/coreelec/ce2a-build.sh" --ci "$mutated" "$TMP/work" "$TMP/evidence" >/dev/null 2>&1; then
    echo "accepted mutated pin: $(basename "$mutated")" >&2; exit 1
  fi
done
[[ ! -e "$TMP/work/source.tar.gz" ]] || { echo 'a mutated pin reached the download step' >&2; exit 1; }
# A shaped manifest with evil provenance must fail schema validation.
python3 - "$ROOT/schemas/coreelec-ce2a-manifest.schema.json" <<'PY'
import copy, json, sys
import jsonschema
s=json.load(open(sys.argv[1]))
h='0'*64
m={'schema_version':1,'status':'PREREQUISITE','source':{'repository':'https://github.com/ashipaek0/CoreELEC.git','fork':{'full_name':'ashipaek0/CoreELEC','required':True,'parent':'CoreELEC/CoreELEC'},'tag':'21.3-Omega','commit':'fc61125e8900ab0c2593a29b615980ed0cd5b939','archive_sha256':'c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a'},'builder':{'dockerfile':'tools/docker/jammy/Dockerfile','dockerfile_sha256':'4f0d46fdf9709230f29e6ea8c423a292024287f653b30f67be01d567a08125a2','base_image':'ubuntu@sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02','base_digest':'sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02','amd64_manifest_digest':'sha256:281c5745f657873d78e5531fc5ba8575f46ab7769b94550ac99543f122679986'},'tuple':{'PROJECT':'Amlogic-ce','DEVICE':'Amlogic-ng','ARCH':'arm','OFFICIAL':'yes'},'artifact':{'path':'target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz','name':'CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz','sha256':h},'image':{'compressed_sha256':h,'raw_bytes':1,'read_only':True},'partition':{'table':'mbr','boot_filesystem':'fat','boot_partition':1},'dtb':{'requested':'sm1_s905x3_4g_1gbit.dtb','installed_name':'dtb.img','sha256':h,'expected_sha256':h,'inspection_tree':'tree','structure':'valid-dtb-dtc'},'kodi':{'classification':'stock-kodi-containing/rejected_for_ashipaos','matches':[]},'runtime':{'runtime_status':'UNRESOLVED','no_kodi_claim':False,'hwdec_status':'UNRESOLVED'},'verification':{'classes':[],'result':'PREREQUISITE_ONLY'},'blocker':{'status':'BLOCKED','reason':'x'},'ci_provenance':{'required':True,'runner':'github-actions','local_build_permitted':False}}
jsonschema.validate(m,s)
evil=copy.deepcopy(m); evil['source']['repository']='https://evil.example/repo.git'
try: jsonschema.validate(evil,s)
except jsonschema.ValidationError: pass
else: raise AssertionError('evil manifest provenance accepted')
PY
printf 'not gzip' > "$TMP/bad.img.gz"
head -c 40 /dev/zero > "$TMP/sm1_s905x3_4g_1gbit.dtb"
printf 'not an image' | gzip -c > "$TMP/valid-gzip.img.gz"
if bash "$ROOT/build/coreelec/ce2a-inspect-image.sh" "$TMP/bad.img.gz" "$PIN" "$TMP/sm1_s905x3_4g_1gbit.dtb" "$TMP/out" >/dev/null 2>&1; then echo 'accepted malformed image' >&2; exit 1; fi
if CE2A_DTB_SHA256=$(sha256sum "$TMP/sm1_s905x3_4g_1gbit.dtb" | cut -d' ' -f1) bash "$ROOT/build/coreelec/ce2a-inspect-image.sh" "$TMP/valid-gzip.img.gz" "$PIN" "$TMP/sm1_s905x3_4g_1gbit.dtb" "$TMP/out-dtb" >/dev/null 2>&1; then echo 'accepted malformed same-name DTB' >&2; exit 1; fi
if CI=true bash "$ROOT/build/coreelec/ce2a-build.sh" --ci "$TMP/missing.json" "$TMP/work" "$TMP/evidence" >/dev/null 2>&1; then echo 'accepted missing pin' >&2; exit 1; fi
if bash "$ROOT/build/coreelec/ce2a-build.sh" "$PIN" "$TMP/work" "$TMP/evidence" >/dev/null 2>&1; then echo 'local build was accepted' >&2; exit 1; fi
# Manifest status mutations are rejected by the schema's literal contract.
python3 - "$ROOT/schemas/coreelec-ce2a-manifest.schema.json" <<'PY'
import json, sys
s=json.load(open(sys.argv[1]))
assert s['properties']['runtime']['properties']['runtime_status']['const']=='UNRESOLVED'
assert s['properties']['kodi']['properties']['classification']['const']=='stock-kodi-containing/rejected_for_ashipaos'
PY
echo 'test-coreelec-ce2a negative: PASS'
