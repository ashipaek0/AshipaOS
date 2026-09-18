#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT/layers/layer2-image/scripts/build-image.sh"
CONFIG="$ROOT/layers/layer2-image/config/image-config.yaml"
PROV="$ROOT/layers/layer2-image/files/a95x-f3-air/provenance.json"

python3 - "$SCRIPT" "$CONFIG" "$PROV" <<'PY'
import json, pathlib, sys
script, config, prov = map(pathlib.Path, sys.argv[1:])
s = script.read_text(); c = config.read_text(); p = json.loads(prov.read_text())
a95x = s[s.index('make_a95x_kernel'):s.index('install_x86_64_bootloader()')]
assert 'mkfs-options' not in a95x
assert 'mkfs.fat -F 16' in a95x
assert 'dd if="$filesystem" of="$image" bs=512 seek=8192' in a95x
assert 'ANDROID!' in a95x and 'page = 2048' in a95x
assert 'secure rootfs extraction failed' in a95x and 'extract an attacker-controlled path' in a95x
assert 'traversal symlink target' in a95x and 'unresolved rootfs path' in a95x
assert 'rootfs_kernel_provenance' in a95x and 'ddr_usb_relationship' in a95x
assert '0x01080000' in a95x and '0x00f00000' in a95x and '0x00000100' in a95x
assert 'root=LABEL=RootFS rw console=ttyS0,115200 console=tty0' in s
# Android legacy v0 layout: name [44:60), cmdline [60:572), ID [572:592).
assert 'header[44:60] = name.ljust(16, b' in a95x
assert 'header[60:572] = cmdline.ljust(512, b' in a95x
assert 'header[572:592] = hashlib.sha1' in a95x
assert 'header[44:64]' not in a95x
assert 'header[60:60 + len(cmdline)]' not in a95x
name_start, name_end = 44, 60
cmdline_start, cmdline_end = 60, 572
id_start, id_end = 572, 592
assert name_end == cmdline_start and cmdline_end == id_start
assert set(range(name_start, name_end)).isdisjoint(range(cmdline_start, cmdline_end))
assert set(range(cmdline_start, cmdline_end)).isdisjoint(range(id_start, id_end))
assert set(range(name_start, name_end)).isdisjoint(range(id_start, id_end))
for forbidden in ('extlinux', 'EFI', 'README', 'COREELEC', 'STORAGE', 'ttyAML0'):
    assert forbidden not in a95x, forbidden
assert 'filesystem: fat16' in c and 'start_sector: 8192' in c and 'start_sector: 532480' in c
assert p['stock_inputs']['meson1.dtb']['sha256'].startswith('264dc24f')
assert p['contract_source']['sha256'] == '9edf06e752ed285e11a565584a2369a39b734df56bd0852ce37eee3d9ea9d16b'
assert p['extraction_evidence']['archive_sha256'] == p['contract_source']['sha256']
assert p['ddr_usb_relationship']['sd_image_action'].startswith('not concatenated')
assert p['generated_inputs']['android_legacy_header'].startswith('AshipaOS self-contained')
print('A95X contract/source negative tests passed')
PY

bad="$(mktemp "${RUNNER_TEMP:-/tmp}/ashipaos-bad-config.XXXXXX")"
trap 'rm -f "$bad" "$bad.img"' EXIT
sed 's/filesystem: fat16/filesystem: vfat/' "$CONFIG" > "$bad"
if ASHIPAOS_IMAGE_CONFIG="$bad" "$SCRIPT" --layout-only "$bad.img" a95x-f3-air >/dev/null 2>&1; then
    echo 'negative test failed: FAT32/vfat override accepted' >&2
    exit 1
fi
if "$SCRIPT" /nonexistent/rootfs.tar.gz a95x-f3-air >/dev/null 2>&1; then
    echo 'negative test failed: missing target rootfs accepted' >&2
    exit 1
fi
printf '%s\n' 'A95X fail-closed negative tests passed'

if [[ $# -eq 1 ]]; then
python3 - "$1" <<'PY'
import hashlib, json, struct, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    data = f.read()
assert data[510:512] == b'\x55\xaa'
start, size = struct.unpack_from('<II', data, 446 + 8)
assert start == 8192 and size == 256 * 2048
b = start * 512
assert data[b+54:b+62] == b'FAT16   '
assert struct.unpack_from('<H', data, b+11)[0] == 512
reserved, fats, root_entries = struct.unpack_from('<HBB', data, b+14)
spf = struct.unpack_from('<H', data, b+22)[0]
root = b + (reserved + fats * spf) * 512
names = {}
for i in range(root_entries):
    e = data[root+i*32:root+(i+1)*32]
    if e[0] == 0: break
    if e[0] != 0xe5 and not (e[11] & 8): names[e[:11].decode('ascii').rstrip()] = e
assert set(names) >= {'AML_AUTOSCRIPT','CFGLOAD','KERNEL.IMG','DTB.IMG','MANIFEST'}
cluster_size = data[b+13] * 512
data_start = root + root_entries * 32
fat_start = b + reserved * 512
def read_file(entry):
    cluster = struct.unpack_from('<H', entry, 26)[0]; size = struct.unpack_from('<I', entry, 28)[0]; out = bytearray()
    while cluster < 0xfff8 and len(out) < size:
        off = data_start + (cluster - 2) * cluster_size
        out += data[off:off+cluster_size]
        cluster = struct.unpack_from('<H', data, fat_start + cluster * 2)[0]
    return bytes(out[:size])
kernel = read_file(names['KERNEL.IMG'])
assert kernel[:8] == b'ANDROID!'
assert struct.unpack_from('<I', kernel, 36)[0] == 2048
assert struct.unpack_from('<I', kernel, 12)[0] == 0x01080000
assert struct.unpack_from('<I', kernel, 20)[0] == 0x01000000
assert struct.unpack_from('<I', kernel, 28)[0] == 0x00f00000
assert struct.unpack_from('<I', kernel, 32)[0] == 0x00000100
cmdline = b'root=LABEL=RootFS rw console=ttyS0,115200 console=tty0'
expected_id = hashlib.sha1(kernel[2048:2048 + struct.unpack_from('<I', kernel, 8)[0]] + kernel[2048 + ((struct.unpack_from('<I', kernel, 8)[0] + 2047) // 2048) * 2048:2048 + ((struct.unpack_from('<I', kernel, 8)[0] + 2047) // 2048) * 2048 + struct.unpack_from('<I', kernel, 16)[0]]).digest()
name = kernel[44:60]
assert name.startswith(b'AshipaOS-A95X')
assert name.rstrip(b'\0') == b'AshipaOS-A95X'
assert kernel[44:60].rstrip(b'\0') == b'AshipaOS-A95X'
assert kernel[60:572].startswith(b'root=LABEL=RootFS rw console=ttyS0,115200 console=tty0')
assert kernel[60:60 + len(cmdline)] == cmdline
assert kernel[44:60].find(cmdline[:4]) == -1
assert kernel[572:592] == expected_id
assert kernel[44:60].find(expected_id[:4]) == -1
assert kernel[60:572].find(expected_id[:4]) == -1
assert set(range(44, 60)).isdisjoint(range(60, 572))
assert set(range(60, 572)).isdisjoint(range(572, 592))
assert set(range(44, 60)).isdisjoint(range(572, 592))
# These shifted reads must not reproduce a valid field at an overlapping offset.
assert kernel[64:64 + len(cmdline)] != cmdline
assert kernel[576:596] != expected_id
manifest = json.loads(read_file(names['MANIFEST']))
assert manifest['files']['KERNEL.IMG'] == hashlib.sha256(kernel).hexdigest()
print('FAT16 A95X image content parsed successfully')
PY
fi
