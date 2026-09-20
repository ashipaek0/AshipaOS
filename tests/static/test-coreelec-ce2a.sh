#!/usr/bin/env bash
# CE-2A static contract: source-build and inspection are isolated and pinned.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PIN=$ROOT/build/coreelec/pin.json
BUILD=$ROOT/build/coreelec/ce2a-build.sh
INSPECT=$ROOT/build/coreelec/ce2a-inspect-image.sh
WF=$ROOT/.github/workflows/coreelec-ce2a.yml
SCHEMA=$ROOT/schemas/coreelec-ce2a-manifest.schema.json
EQUIV=$ROOT/docs/coreelec-pax-utils-equivalence.md
fail(){ echo "FAIL: $*" >&2; exit 1; }
[[ -f "$EQUIV" ]] || fail 'pax-utils equivalence evidence exists'
[[ -x "$BUILD" && -x "$INSPECT" ]] || fail 'CE-2A scripts must be executable'
bash -n "$BUILD" "$INSPECT" || fail 'shell syntax'
python3 - "$PIN" "$SCHEMA" <<'PY'
import json, re, sys
p=json.load(open(sys.argv[1])); s=json.load(open(sys.argv[2]))
assert p['source']['fork']=={'full_name':'ashipaek0/CoreELEC','required':True,'parent':'CoreELEC/CoreELEC'}
assert p['source']['ref']=={'type':'tag','value':'21.3-Omega'}
assert p['source']['commit']=='fc61125e8900ab0c2593a29b615980ed0cd5b939'
assert p['source']['archive']['sha256']=='c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a'
assert p['builder']['dockerfile']['sha256']=='4f0d46fdf9709230f29e6ea8c423a292024287f653b30f67be01d567a08125a2'
assert p['builder']['base_image']['digest']=='sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02'
assert p['build']=={'PROJECT':'Amlogic-ce','DEVICE':'Amlogic-ng','ARCH':'arm','OFFICIAL':'yes'}
assert p['artifact']['path']=='target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz'
for text in (open(sys.argv[2]).read(),):
 for x in ('UNRESOLVED','stock-kodi-containing/rejected_for_ashipaos','local_build_permitted','dtb.img','valid-dtb-dtc','expected_sha256','281c5745f657873d78e5531fc5ba8575f46ab7769b94550ac99543f122679986'): assert x in text
PY
for needle in '108362d29668d25cf7b0cadc63b15a4c1cfc0dbc71adc151b33c5fe7dece939' 'd49fa503588cb9a89eda7eb7141b65507fa126ce' 'Common files: `58`' 'Differing common files: `0`' '02c1539f4b22ac01f5718f838433b6c920fd4932a7bacf4478279b4c7cf8dca7'; do grep -Fq "$needle" "$EQUIV" || fail "equivalence evidence missing $needle"; done
for needle in 'CI=true' 'docker build --pull=false' 'archive_sha' 'base_digest' 'artifact_count' 'Amlogic-ce' 'Amlogic-ng' 'ARCH=arm' 'OFFICIAL=yes'; do grep -q "$needle" "$BUILD" || fail "build missing $needle"; done
for needle in 'gzip -t' 'dtc -I dtb -O dts' '/dts-v1/' 'root node' 'CE2A_DTB_SHA256' 'read-only' 'sm1_s905x3_4g_1gbit.dtb' 'inspection-tree.txt' 'stock-kodi-containing/rejected_for_ashipaos' 'runtime_status'; do grep -q "$needle" "$INSPECT" || fail "inspection missing $needle"; done
for needle in 'workflow_dispatch' 'pull_request' 'Static and negative gates (before build)' 'Validate generated CE-2A manifest' 'validate-ce2a-manifest.py' 'coreelec-ce2a-manifest.schema.json' 'if: always()' 'actions/checkout@' 'actions/upload-artifact@'; do grep -q "$needle" "$WF" || fail "workflow missing $needle"; done
if grep -E '^\s*uses: actions/[^@]+@(main|master|v[0-9])' "$WF" >/dev/null; then fail 'workflow uses mutable action ref'; fi
if grep -q 'build-images.yml\|build-x86\|build-pi\|layers/layer' "$WF"; then fail 'workflow is not isolated'; fi
if grep -qE 'losetup|mount |chroot|sudo ' "$BUILD" "$INSPECT"; then fail 'privileged/local image operation present'; fi
bash "$ROOT/tests/static/test-coreelec-ce2a-bind-paths.sh" || fail 'relative Docker bind-path regression'
echo 'test-coreelec-ce2a: PASS'
