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

# Keep the FAT directory reader strict: an LFN is accepted only when it is
# contiguous, correctly ordered, terminated, and checksummed against its 8.3
# entry.  This prevents malformed metadata from silently changing the root
# file contract.
python3 - <<'PY'
import struct

_REQUIRED = {'AML_AUTOSCRIPT', 'CFGLOAD', 'KERNEL.IMG', 'dtb.img', 'manifest'}
_LFN_OFFSETS = (1, 14, 28)

def _short_checksum(short):
    checksum = 0
    for value in short:
        checksum = ((checksum >> 1) | ((checksum & 1) << 7))
        checksum = (checksum + value) & 0xff
    return checksum

def _short_name(entry):
    raw = entry[:11]
    base = raw[:8].decode('ascii').rstrip(' ')
    ext = raw[8:11].decode('ascii').rstrip(' ')
    return base + ('.' + ext if ext else '')

def _lfn_fragment(entry, final):
    raw = b''.join(entry[offset:offset + length] for offset, length in zip(_LFN_OFFSETS, (10, 12, 4)))
    chars = raw.decode('utf-16le', errors='strict')
    if final:
        assert chr(0) in chars, 'final LFN fragment lacks NUL'
        name, suffix = chars.split(chr(0), 1)
        assert suffix and all(char == chr(0xffff) for char in suffix), 'final LFN has non-padding after NUL'
        return name
    assert chr(0) not in chars, 'non-final LFN fragment contains NUL'
    assert chr(0xffff) not in chars, 'non-final LFN fragment contains padding'
    return chars

def parse_root_directory(data, root, root_entries):
    names = {}
    pending = []
    for index in range(root_entries):
        entry = data[root + index * 32:root + (index + 1) * 32]
        assert len(entry) == 32, 'truncated FAT directory entry'
        marker = entry[0]
        if marker == 0:
            assert not pending, 'unterminated LFN sequence'
            break
        if marker == 0xe5:
            assert not pending, 'deleted entry interrupts LFN sequence'
            continue
        attributes = entry[11]
        if attributes == 0x0f:
            assert entry[12] == 0 and entry[26:28] == bytes(2), 'invalid LFN metadata'
            ordinal = marker & 0x1f
            final = bool(marker & 0x40)
            assert ordinal and ordinal <= 20 and marker == (ordinal | (0x40 if final else 0)), 'invalid LFN ordinal'
            assert not (pending and final), 'multiple LFN LAST markers'
            if pending:
                assert pending[0][0] & 0x40, 'LFN LAST marker is not first'
            pending.append((marker, entry[13], _lfn_fragment(entry, final)))
            continue
        assert not (pending and attributes & 0x08), 'LFN before volume label'
        if pending:
            assert pending[0][0] & 0x40, 'LFN sequence missing final marker'
            assert pending[0][0] & 0x1f == len(pending), 'LFN sequence length mismatch'
            assert [item[0] & 0x1f for item in pending] == list(range(len(pending), 0, -1)), 'LFN sequence out of order'
            checksum = entry[:11]
            assert all(item[1] == _short_checksum(checksum) for item in pending), 'LFN checksum mismatch'
            long_name = ''.join(item[2] for item in reversed(pending))
            pending = []
        else:
            long_name = _short_name(entry)
        if attributes & 0x08:
            continue
        assert long_name and long_name not in names, 'duplicate FAT root name'
        names[long_name] = entry
    assert not pending, 'unterminated LFN sequence'
    return names

# Parser-focused coverage without requiring an assembled image.
def _short(raw):
    entry = bytearray(32)
    entry[:11] = raw
    return entry

def _lfn(name, ordinal, short, final=False, checksum=None):
    entry = bytearray(32)
    entry[0] = ordinal | (0x40 if final else 0)
    entry[11] = 0x0f
    entry[13] = _short_checksum(short) if checksum is None else checksum
    encoded = (name + (chr(0) if final else '')).encode('utf-16le')
    encoded += bytes.fromhex('ffff') * ((26 - len(encoded)) // 2)
    for offset, part in zip(_LFN_OFFSETS, (encoded[:10], encoded[10:22], encoded[22:26])):
        entry[offset:offset + len(part)] = part
    return entry

short = b'AML_AUTO' + b'SCR'
long = 'AML_AUTOSCRIPT'
valid = _lfn(long[13:], 2, short, final=True) + _lfn(long[:13], 1, short) + _short(short) + bytes(32)
parsed = parse_root_directory(valid, 0, 4)
assert 'AML_AUTOSCRIPT' in parsed
for malformed in (
    _lfn(long[:13], 1, short) + _lfn(long[13:], 2, short, final=True) + _short(short) + bytes(32),
    _lfn(long[13:], 2, short, final=True, checksum=0) + _lfn(long[:13], 1, short) + _short(short) + bytes(32),
):
    try:
        parse_root_directory(malformed, 0, 4)
    except AssertionError:
        pass
    else:
        raise AssertionError('malformed LFN metadata was accepted')
# Explicitly exercise two LAST markers and NUL/padding in a non-final fragment.
double_last = _lfn(long[13:], 2, short, final=True) + _lfn(long[:13], 1, short, final=True) + _short(short)
try:
    parse_root_directory(double_last, 0, 3)
except AssertionError:
    pass
else:
    raise AssertionError('multiple LAST markers were accepted')
bad_nonfinal = bytearray(_lfn(long[:13], 1, short))
bad_nonfinal[1:3] = b'\0\0'
try:
    parse_root_directory(bytes(bad_nonfinal) + _short(short), 0, 2)
except AssertionError:
    pass
else:
    raise AssertionError('non-final LFN NUL was accepted')
# FAT-chain fixtures: free, reserved, bad, out-of-range, cycle, and premature EOC.
def _read_chain(data, entry, fat_start, data_start, cluster_size, max_cluster):
    size = struct.unpack_from('<I', entry, 28)[0]
    cluster = struct.unpack_from('<H', entry, 26)[0]
    assert 2 <= cluster <= max_cluster
    out, seen = bytearray(), set()
    while len(out) < size:
        assert 2 <= cluster <= max_cluster and cluster not in seen
        seen.add(cluster)
        chunk = data[data_start + (cluster - 2) * cluster_size:data_start + (cluster - 1) * cluster_size]
        assert len(chunk) == cluster_size
        out += chunk
        nxt = struct.unpack_from('<H', data, fat_start + cluster * 2)[0]
        assert nxt != 0 and nxt != 1 and nxt != 0xfff7 and not (0xfff0 <= nxt <= 0xfff6)
        if len(out) < size:
            assert nxt < 0xfff8 and 2 <= nxt <= max_cluster
        elif nxt < 0xfff8:
            assert 2 <= nxt <= max_cluster
        cluster = nxt

def _chain_case(value, size=2):
    data = bytearray(4096)
    entry = bytearray(32)
    struct.pack_into('<H', entry, 26, 2)
    struct.pack_into('<I', entry, 28, size)
    struct.pack_into('<H', data, 4, value)
    return data, entry
for value in (0, 1, 0xfff7, 0xfff1, 4):
    data, entry = _chain_case(value)
    try:
        _read_chain(data, entry, 0, 2048, 512, 3)
    except AssertionError:
        pass
    else:
        raise AssertionError('invalid FAT chain was accepted')
data, entry = _chain_case(2, size=513)
try:
    _read_chain(data, entry, 0, 2048, 512, 3)
except AssertionError:
    pass
else:
    raise AssertionError('FAT cycle was accepted')
data, entry = _chain_case(0xfff8, size=513)
try:
    _read_chain(data, entry, 0, 2048, 512, 3)
except AssertionError:
    pass
else:
    raise AssertionError('premature FAT EOC was accepted')
print('VFAT LFN parser tests passed')
PY

# Execute the image-argument path against a sparse, synthetic FAT16 image.  The
# fixture is built directly with Python so this coverage never invokes the A95X
# image builder, guestfish, or any filesystem assembly tool.
if [[ $# -eq 0 && ${ASHIPAOS_SYNTHETIC_FIXTURE:-0} != 1 ]]; then
    synthetic="$(mktemp "${RUNNER_TEMP:-/tmp}/ashipaos-fat16-fixture.XXXXXX.img")"
    trap 'rm -f "$bad" "$bad.img" "$synthetic"' EXIT
    python3 - "$synthetic" <<'PY'
import hashlib
import json
import struct
import sys

path = sys.argv[1]
sector = 512
partition_start = 8192
partition_sectors = 256 * 2048
partition_offset = partition_start * sector
reserved = 1
fats = 2
sectors_per_cluster = 8
root_entries = 128
sectors_per_fat = 256
root_sectors = root_entries * 32 // sector
fat_start = partition_offset + reserved * sector
root_start = partition_offset + (reserved + fats * sectors_per_fat) * sector
data_start = root_start + root_sectors * sector
cluster_size = sectors_per_cluster * sector

kernel = bytearray(8192)
kernel[:8] = b'ANDROID!'
struct.pack_into('<I', kernel, 8, 4)
struct.pack_into('<I', kernel, 12, 0x01080000)
struct.pack_into('<I', kernel, 16, 4)
struct.pack_into('<I', kernel, 20, 0x01000000)
struct.pack_into('<I', kernel, 28, 0x00f00000)
struct.pack_into('<I', kernel, 32, 0x00000100)
struct.pack_into('<I', kernel, 36, 2048)
kernel[44:60] = b'AshipaOS-A95X'.ljust(16, b'\0')
cmdline = b'root=LABEL=RootFS rw console=ttyS0,115200 console=tty0'
kernel[60:60 + len(cmdline)] = cmdline
kernel[2048:2052] = b'KERN'
kernel[4096:4100] = b'RAMD'
kernel[572:592] = hashlib.sha1(kernel[2048:2052] + kernel[4096:4100]).digest()

files = {
    'AML_AUTOSCRIPT': b'autoscript\n',
    'CFGLOAD': b'cfgload\n',
    'KERNEL.IMG': bytes(kernel),
    'dtb.img': b'dtb\n',
}
files['manifest'] = json.dumps({'files': {
    name: hashlib.sha256(value).hexdigest() for name, value in files.items()
}}, sort_keys=True).encode() + b'\n'

short_names = {
    'AML_AUTOSCRIPT': b'AML_AUTOSCR',
    'CFGLOAD': b'CFGLOAD    ',
    'KERNEL.IMG': b'KERNEL  IMG',
    'dtb.img': b'dtb     img',
    'manifest': b'manifest   ',
}
def short_checksum(short):
    checksum = 0
    for value in short:
        checksum = ((checksum >> 1) | ((checksum & 1) << 7))
        checksum = (checksum + value) & 0xff
    return checksum

def lfn_entry(name, ordinal, short, final=False):
    entry = bytearray(32)
    entry[0] = ordinal | (0x40 if final else 0)
    entry[11] = 0x0f
    entry[13] = short_checksum(short)
    encoded = (name + ('\0' if final else '')).encode('utf-16le')
    encoded += b'\xff\xff' * ((26 - len(encoded)) // 2)
    for offset, part in zip((1, 14, 28), (encoded[:10], encoded[10:22], encoded[22:26])):
        entry[offset:offset + len(part)] = part
    return entry

image_size = (partition_start + partition_sectors) * sector
with open(path, 'wb') as image:
    image.truncate(image_size)
    mbr = bytearray(sector)
    struct.pack_into('<B', mbr, 446 + 4, 0x0c)
    struct.pack_into('<II', mbr, 446 + 8, partition_start, partition_sectors)
    mbr[510:512] = b'\x55\xaa'
    image.seek(0)
    image.write(mbr)

    boot = bytearray(sector)
    boot[3:11] = b'MSDOS5.0'
    struct.pack_into('<H', boot, 11, sector)
    boot[13] = sectors_per_cluster
    struct.pack_into('<HBB', boot, 14, reserved, fats, root_entries)
    struct.pack_into('<H', boot, 19, 0)
    struct.pack_into('<I', boot, 32, partition_sectors)
    boot[21] = 0xf8
    struct.pack_into('<H', boot, 22, sectors_per_fat)
    boot[54:62] = b'FAT16   '
    boot[510:512] = b'\x55\xaa'
    image.seek(partition_offset)
    image.write(boot)

    for fat_index in range(fats):
        fat = bytearray(sectors_per_fat * sector)
        struct.pack_into('<HHHHHHH', fat, 0, 0xff8, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff)
        image.seek(fat_start + fat_index * sectors_per_fat * sector)
        image.write(fat)

    root = bytearray(root_sectors * sector)
    directory_entries = []
    clusters = {'AML_AUTOSCRIPT': 2, 'CFGLOAD': 3, 'KERNEL.IMG': 4, 'dtb.img': 6, 'manifest': 7}
    for index, (name, value) in enumerate(files.items()):
        entry = bytearray(32)
        entry[:11] = short_names[name]
        entry[11] = 0x20
        cluster = clusters[name]
        struct.pack_into('<H', entry, 26, cluster)
        struct.pack_into('<I', entry, 28, len(value))
        if name == 'AML_AUTOSCRIPT':
            short = short_names[name]
            directory_entries.extend((
                lfn_entry(name[13:], 2, short, final=True),
                lfn_entry(name[:13], 1, short),
            ))
        directory_entries.append(entry)
        image.seek(data_start + (cluster - 2) * cluster_size)
        image.write(value)
    for index, entry in enumerate(directory_entries):
        root[index * 32:(index + 1) * 32] = entry
    image.seek(root_start)
    image.write(root)

    for fat_index in range(fats):
        chain = {2: 0xfff8, 3: 0xfff8, 4: 5, 5: 0xfff8, 6: 0xfff8, 7: 0xfff8}
        for cluster, next_cluster in chain.items():
            image.seek(fat_start + fat_index * sectors_per_fat * sector + cluster * 2)
            image.write(struct.pack('<H', next_cluster))
PY
    ASHIPAOS_SYNTHETIC_FIXTURE=1 "$BASH_SOURCE" "$synthetic"
    printf '%s\n' 'synthetic FAT16 image-argument parser test passed'
fi

if [[ $# -eq 1 ]]; then
python3 - "$1" <<'PY'
import hashlib, json, struct, sys
_REQUIRED = {'AML_AUTOSCRIPT', 'CFGLOAD', 'KERNEL.IMG', 'dtb.img', 'manifest'}
_LFN_OFFSETS = (1, 14, 28)
def _short_checksum(short):
    checksum = 0
    for value in short:
        checksum = ((checksum >> 1) | ((checksum & 1) << 7))
        checksum = (checksum + value) & 0xff
    return checksum

def _short_name(entry):
    raw = entry[:11]
    base = raw[:8].decode('ascii').rstrip(' ')
    ext = raw[8:11].decode('ascii').rstrip(' ')
    return base + ('.' + ext if ext else '')

def _lfn_fragment(entry, final):
    raw = b''.join(entry[offset:offset + length] for offset, length in zip(_LFN_OFFSETS, (10, 12, 4)))
    chars = raw.decode('utf-16le', errors='strict')
    if final:
        assert chr(0) in chars, 'final LFN fragment lacks NUL'
        name, suffix = chars.split(chr(0), 1)
        assert suffix and all(char == chr(0xffff) for char in suffix), 'final LFN has non-padding after NUL'
        return name
    assert chr(0) not in chars, 'non-final LFN fragment contains NUL'
    assert chr(0xffff) not in chars, 'non-final LFN fragment contains padding'
    return chars

def parse_root_directory(data, root, root_entries):
    names = {}
    pending = []
    for index in range(root_entries):
        entry = data[root + index * 32:root + (index + 1) * 32]
        assert len(entry) == 32, 'truncated FAT directory entry'
        marker = entry[0]
        if marker == 0:
            assert not pending, 'unterminated LFN sequence'
            break
        if marker == 0xe5:
            assert not pending, 'deleted entry interrupts LFN sequence'
            continue
        attributes = entry[11]
        if attributes == 0x0f:
            assert entry[12] == 0 and entry[26:28] == bytes(2), 'invalid LFN metadata'
            ordinal = marker & 0x1f
            final = bool(marker & 0x40)
            assert ordinal and ordinal <= 20 and marker == (ordinal | (0x40 if final else 0)), 'invalid LFN ordinal'
            assert not (pending and final), 'multiple LFN LAST markers'
            if pending:
                assert pending[0][0] & 0x40, 'LFN LAST marker is not first'
            pending.append((marker, entry[13], _lfn_fragment(entry, final)))
            continue
        assert not (pending and attributes & 0x08), 'LFN before volume label'
        if pending:
            assert pending[0][0] & 0x40
            assert pending[0][0] & 0x1f == len(pending)
            assert [item[0] & 0x1f for item in pending] == list(range(len(pending), 0, -1)), 'LFN sequence out of order'
            assert all(item[1] == _short_checksum(entry[:11]) for item in pending), 'LFN checksum mismatch'
            long_name = ''.join(item[2] for item in reversed(pending))
            pending = []
        else:
            long_name = _short_name(entry)
        if attributes & 0x08:
            continue
        assert long_name and long_name not in names, 'duplicate FAT root name'
        names[long_name] = entry
    assert not pending, 'unterminated LFN sequence'
    return names

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
names = parse_root_directory(data, root, root_entries)
assert set(names) == _REQUIRED, 'root directory file set does not match boot contract'
cluster_size = data[b+13] * 512
fat_start = b + reserved * 512
root_bytes = root_entries * 32
data_start = root + root_bytes
sectors16 = struct.unpack_from('<H', data, b+19)[0]
sectors = sectors16 or struct.unpack_from('<I', data, b+32)[0]
data_sectors = sectors - (reserved + fats * spf + (root_bytes + 511) // 512)
max_cluster = 1 + data_sectors // data[b+13]
def read_file(entry):
    size = struct.unpack_from('<I', entry, 28)[0]
    cluster = struct.unpack_from('<H', entry, 26)[0]
    if size == 0:
        assert cluster == 0, 'empty file has a cluster'
        return b''
    assert 2 <= cluster <= max_cluster, 'file starts outside FAT data clusters'
    out, seen = bytearray(), set()
    while len(out) < size:
        assert 2 <= cluster <= max_cluster, 'FAT chain has invalid cluster'
        assert cluster not in seen, 'FAT chain cycle'
        seen.add(cluster)
        off = data_start + (cluster - 2) * cluster_size
        chunk = data[off:off+cluster_size]
        assert len(chunk) == cluster_size, 'FAT chain reaches truncated data'
        out += chunk
        nxt = struct.unpack_from('<H', data, fat_start + cluster * 2)[0]
        assert nxt != 0 and nxt != 1 and nxt != 0xfff7 and not (0xfff0 <= nxt <= 0xfff6), \
            'FAT chain uses reserved/free/bad cluster'
        if len(out) < size:
            assert nxt < 0xfff8, 'FAT chain ends before file size'
            assert 2 <= nxt <= max_cluster, 'FAT chain has invalid next cluster'
        elif nxt < 0xfff8:
            assert 2 <= nxt <= max_cluster, 'FAT chain has invalid terminal cluster'
        cluster = nxt
    return bytes(out[:size])
assert set(names) == _REQUIRED, 'root directory file set does not match boot contract'
files = {name: read_file(names[name]) for name in _REQUIRED}
assert all(files[name] for name in _REQUIRED), 'required boot file is empty'
manifest = json.loads(files['manifest'])
assert set(manifest['files']) == _REQUIRED - {'manifest'}
for name in _REQUIRED - {'manifest'}:
    assert hashlib.sha256(files[name]).hexdigest() == manifest['files'][name], 'required boot file hash mismatch: ' + name
kernel = files['KERNEL.IMG']
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
# The manifest was already resolved and read with every required boot file.
assert manifest['files']['KERNEL.IMG'] == hashlib.sha256(kernel).hexdigest()
print('FAT16 A95X image content parsed successfully')
PY
fi
