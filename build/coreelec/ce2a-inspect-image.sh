#!/usr/bin/env bash
# CE-2A: read-only Generic image inspection; userspace only.
set -Eeuo pipefail
[[ $# -eq 4 ]] || { echo "Usage: $0 GENERIC.img.gz PIN.json DTB_FILE OUTPUT_DIR" >&2; exit 64; }
IMAGE=$1; PIN=$2; DTB=$3; OUT=$4
[[ -f "$IMAGE" && -f "$PIN" && -f "$DTB" ]] || { echo "missing inspection input" >&2; exit 2; }
[[ "$(basename "$DTB")" == sm1_s905x3_4g.dtb ]] || { echo "DTB basename must be sm1_s905x3_4g.dtb" >&2; exit 2; }
expected_dtb_sha256=${CE2A_DTB_SHA256:-}
[[ "$expected_dtb_sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "CE2A_DTB_SHA256 must bind the expected DTB hash" >&2; exit 2; }
mkdir -p "$OUT"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
raw="$tmp/generic.img"
gzip -t "$IMAGE" || { echo "malformed gzip image" >&2; exit 1; }
gzip -dc -- "$IMAGE" > "$raw"
command -v dtc >/dev/null 2>&1 || { echo "dtc is required for DTB structural validation" >&2; exit 2; }
dtc -I dtb -O dts -o "$tmp/dtb.dts" "$DTB" >/dev/null 2>&1 || { echo "malformed DTB" >&2; exit 1; }
grep -Fqx '/dts-v1/;' "$tmp/dtb.dts" || { echo "DTB missing /dts-v1/" >&2; exit 1; }
grep -Eq '^/ \{' "$tmp/dtb.dts" || { echo "DTB missing root node" >&2; exit 1; }
export IMAGE PIN DTB OUT RAW=$raw EXPECTED_DTB_SHA256=$expected_dtb_sha256
python3 - <<'PY'
import hashlib, json, os, struct, sys
from pathlib import Path
raw=Path(os.environ['RAW']).read_bytes(); pin=json.load(open(os.environ['PIN'],encoding='utf8'))
out=Path(os.environ['OUT']); dtb=Path(os.environ['DTB']).read_bytes(); expected_dtb_sha256=os.environ['EXPECTED_DTB_SHA256']
if len(raw)<512: raise SystemExit('malformed image: shorter than a sector')

def u16(o): return struct.unpack_from('<H',raw,o)[0]
def u32(o): return struct.unpack_from('<I',raw,o)[0]
parts=[]; table='mbr'
if raw[510:512] != b'\x55\xaa': raise SystemExit('malformed image: missing MBR signature')
for i in range(4):
 o=446+i*16; typ=raw[o+4]; start=u32(o+8); size=u32(o+12)
 if size: parts.append({'number':i+1,'type':typ,'start_sector':start,'sectors':size})
if raw[0x1be+4] == 0xee:
 table='gpt'; parts=[]
 # GPT entries, enough for inspection metadata; reject truncated tables.
 if raw[512:520] != b'EFI PART': raise SystemExit('malformed GPT')
 n=struct.unpack_from('<I',raw,512+80)[0]; es=struct.unpack_from('<I',raw,512+84)[0]
 for i in range(min(n,128)):
  o=512*2+i*es
  if o+es>len(raw): raise SystemExit('truncated GPT')
  first=struct.unpack_from('<Q',raw,o+32)[0]; last=struct.unpack_from('<Q',raw,o+40)[0]
  if first and last>=first: parts.append({'number':i+1,'type_guid':raw[o:o+16].hex(),'start_sector':first,'sectors':last-first+1})

def fat_info(p):
 base=p['start_sector']*512
 if base+64>len(raw) or raw[base+510:base+512] != b'\x55\xaa': return None
 bps=u16(base+11); spc=raw[base+13]; reserved=u16(base+14); fats=raw[base+16]; root=u16(base+17); total=u16(base+19) or u32(base+32); fatsz=u16(base+22) or u32(base+36)
 if bps not in (512,1024,2048,4096) or not spc or not fats or not fatsz: return None
 root_secs=((root*32+bps-1)//bps); data_secs=total-(reserved+fats*fatsz+root_secs); clusters=data_secs//spc
 kind='fat32' if clusters>=65525 else ('fat16' if clusters>=4085 else 'fat12')
 return {'kind':kind,'bytes_per_sector':bps,'sectors_per_cluster':spc,'reserved_sectors':reserved,'fat_count':fats,'fat_sectors':fatsz,'root_entries':root,'base':base,'root_dir_sectors':root_secs,'data_start':base+(reserved+fats*fatsz+root_secs)*bps}
infos=[]
for p in parts:
 fi=fat_info(p)
 if fi: p['filesystem']=fi['kind']; infos.append((p,fi))
if not infos: raise SystemExit('no FAT boot partition found')
boot,fi=infos[0]
# Conservative byte scan: stock Generic is intentionally rejected even if a tool cannot decode every FS.
low=raw.lower(); matches=[]
for needle in (b'kodi',b'usr/bin/kodi',b'kodi.service',b'kodi.bin'):
 if needle in low: matches.append(needle.decode())
if not matches: matches=['stock Generic image requires Kodi-content review']
sha=lambda b: hashlib.sha256(b).hexdigest()
if sha(dtb) != expected_dtb_sha256: raise SystemExit('DTB hash does not match CE2A_DTB_SHA256')
(out/'dtb.img').write_bytes(dtb)
(out/'inspection-tree.txt').write_text('\n'.join([
 'CE-2A read-only inspection tree',f'raw_bytes={len(raw)}',f'partition_table={table}',f'boot_partition={boot["number"]}',f'boot_filesystem={fi["kind"]}',f'dtb=sm1_s905x3_4g.dtb -> dtb.img',f'dtb_structure=valid-dtb-dtc',f'dtb_sha256={sha(dtb)}',f'kodi_scan={";".join(matches)}'])+'\n',encoding='utf8')
artifact=pin['artifact']['name']
manifest={'schema_version':1,'status':'PREREQUISITE','source':{'repository':pin['source']['repository'],'fork':pin['source']['fork'],'tag':pin['source']['ref']['value'],'commit':pin['source']['commit'],'archive_sha256':pin['source']['archive']['sha256']},'builder':{'dockerfile':pin['builder']['dockerfile']['path'],'dockerfile_sha256':pin['builder']['dockerfile']['sha256'],'base_image':pin['builder']['base_image']['pinned_reference'],'base_digest':pin['builder']['base_image']['digest'],'amd64_manifest_digest':pin['builder']['base_image']['linux_amd64_manifest_digest']},'tuple':pin['build'],'artifact':{'path':pin['artifact']['path'],'name':artifact,'sha256':sha(Path(os.environ['IMAGE']).read_bytes())},'image':{'compressed_sha256':sha(Path(os.environ['IMAGE']).read_bytes()),'raw_bytes':len(raw),'read_only':True},'partition':{'table':table,'boot_filesystem':'fat','boot_partition':boot['number'],'entries':parts},'dtb':{'requested':'sm1_s905x3_4g.dtb','installed_name':'dtb.img','sha256':sha(dtb),'expected_sha256':expected_dtb_sha256,'inspection_tree':str(out/'inspection-tree.txt'),'structure':'valid-dtb-dtc'},'kodi':{'classification':'stock-kodi-containing/rejected_for_ashipaos','matches':matches},'runtime':{'runtime_status':'UNRESOLVED','no_kodi_claim':False,'hwdec_status':'UNRESOLVED'},'verification':{'classes':['STATIC','BUILD','INSPECTION'],'result':'PREREQUISITE_ONLY'},'blocker':{'status':'BLOCKED','reason':'Stock Generic output contains Kodi; no AshipaOS no-Kodi runtime or hardware integration has been selected.'},'ci_provenance':{'required':True,'runner':'github-actions','local_build_permitted':False}}
(out/'ce2a-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
print(json.dumps({'manifest':str(out/'ce2a-manifest.json'),'boot_filesystem':fi['kind'],'dtb_sha256':sha(dtb),'kodi_classification':manifest['kodi']['classification']}))
PY
