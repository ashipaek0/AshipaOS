#!/usr/bin/env python3
"""Validate the extracted ISO tree against xorriso's plain El Torito report."""
import hashlib
import mmap
import pathlib
import re
import subprocess
import sys


def fail(message):
    raise SystemExit(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate(report, tree, iso, boot_hybrid, mdir='mdir', zstd='zstd'):
    tree, iso = pathlib.Path(tree), pathlib.Path(iso)
    def field(name):
        matches = re.findall(r'^' + re.escape(name) + r'\s*:\s*(.*)$', report, re.M)
        if len(matches) != 1:
            fail('missing or duplicate ' + name)
        return matches[0]
    catalog = field('El Torito catalog').split()
    catalog_path = field('El Torito cat path')
    if len(catalog) != 2 or not all(x.isdigit() for x in catalog):
        fail('invalid El Torito catalog LBA')
    if catalog_path != '/boot.catalog':
        fail('unexpected El Torito catalog path')
    iso_file = iso.open('rb')
    image = mmap.mmap(iso_file.fileno(), 0, access=mmap.ACCESS_READ)
    iso_file.close()
    # Compare GRUB's BIOS bootstrap, excluding the partition table/signature
    # and the 4-byte boot-info patch at 0x1b0..0x1b3 applied by xorriso.
    template = pathlib.Path(boot_hybrid).read_bytes()
    if len(template) < 440 or not any(template[:440]):
        fail('invalid GRUB boot_hybrid.img template')
    if len(image) < 32768 or image[510:512] != b'\x55\xaa':
        fail('missing or truncated ISO system-area MBR')
    if image[:432] != template[:432] or image[436:440] != template[436:440]:
        fail('GRUB BIOS hybrid bootstrap does not match boot_hybrid.img')
    records = [image[offset:offset+16] for offset in range(446, 510, 16)]
    if not any(row[0] in (0, 0x80) and row[4] != 0 and int.from_bytes(row[8:12], 'little') > 0 and int.from_bytes(row[12:16], 'little') > 0 for row in records):
        fail('hybrid MBR partition table missing or invalid')
    def entry(path):
        if not path.startswith('/') or '..' in pathlib.PurePosixPath(path).parts:
            fail('invalid catalog image path')
        asset = tree / path.lstrip('/')
        if not asset.is_file() or not asset.stat().st_size:
            fail('catalog image missing: ' + path)
        return asset.read_bytes()
    catalog_bytes = entry(catalog_path)
    if catalog_bytes != image[int(catalog[0])*2048:int(catalog[0])*2048+len(catalog_bytes)]:
        fail('El Torito catalog LBA differs from catalog asset')
    if len(catalog_bytes) < 32 or catalog_bytes[0] != 1 or catalog_bytes[30:32] != b'\x55\xaa':
        fail('invalid El Torito catalog validation entry')
    if 'Pltf' not in field('El Torito images'):
        fail('El Torito image header missing')
    boots = re.findall(r'^El Torito boot img\s*:\s*(.*)$', report, re.M)
    paths = re.findall(r'^El Torito img path\s*:\s*(\d+)\s+(\S+)\s*$', report, re.M)
    if len(boots) != 2 or len(paths) != 2 or len(set(paths)) != 2:
        fail('missing or duplicate El Torito image mapping')
    path_by_id = dict(paths)
    for number, platform in [('1', 'BIOS'), ('2', 'UEFI')]:
        row = next((b.split() for b in boots if b.split()[0] == number), None)
        if not row or len(row) != 8 or row[1:4] != [platform, 'y', 'none'] or not row[6].isdigit() or not row[7].isdigit() or int(row[6]) < 1:
            fail('invalid ' + platform + ' El Torito platform/load/LBA')
        path = path_by_id.get(number)
        if path is None:
            fail('missing ' + platform + ' catalog path')
        if platform == 'BIOS' and path not in ('/boot/grub/i386-pc/eltorito.img', '/eltorito.img'):
            fail('unexpected BIOS boot image path')
        if platform == 'UEFI' and path not in ('/efi.img', '/boot/grub/efi.img'):
            fail('unexpected UEFI boot image path')
        content = entry(path)
        lba = int(row[7]); offset = lba * 2048
        if content != image[offset:offset+len(content)]:
            fail(platform + ' catalog LBA differs from inspected image')
        if platform == 'UEFI':
            if content[510:512] != b'\x55\xaa' or content[54:62] != b'FAT16   ' and content[82:90] != b'FAT32   ':
                fail('UEFI image is not FAT')
            check = subprocess.run([mdir, '-i', str(tree / path.lstrip('/')), '::/EFI/BOOT/BOOTX64.EFI'], capture_output=True)
            if check.returncode:
                fail('UEFI FAT image missing BOOTX64.EFI')
    required = ['boot/vmlinuz', 'boot/initramfs.gz', 'boot/grub/grub.cfg', 'install/appliance.img.zst', 'install/appliance.img.manifest', 'EFI/BOOT/BOOTX64.EFI']
    for relative in required:
        if not (tree / relative).is_file() or (tree / relative).stat().st_size == 0:
            fail('ISO asset missing: ' + relative)
    config = (tree / 'boot/grub/grub.cfg').read_text()
    menus = re.findall(r'^menuentry\s+[^\n{]+\{([^{}]*)\}', config, re.M | re.S)
    if len(menus) != 2:
        fail('expected normal and force GRUB entries')
    for number, menu in enumerate(menus):
        linux = re.findall(r'^\s*linux\s+(/\S+)(.*)$', menu, re.M)
        initrd = re.findall(r'^\s*initrd\s+(\S+)\s*$', menu, re.M)
        if len(linux) != 1 or linux[0][0] != '/boot/vmlinuz' or initrd != ['/boot/initramfs.gz']:
            fail('GRUB linux/initrd directive missing')
        if (number == 1) != ('ashipaos.force=1' in linux[0][1]):
            fail('GRUB force reinstall kernel argument missing or misplaced')
    for asset in tree.rglob('*'):
        relative = asset.relative_to(tree).as_posix().lower()
        if re.search(r'(^|[/_.-])(d-i|install\.amd|preseed|netinst|isolinux)([/_.-]|$)', relative):
            fail('legacy Debian Installer asset: ' + relative)
        if asset.is_file() and asset.suffix.lower() in ('.cfg', '.conf', '.txt'):
            text = asset.read_text(errors='replace').lower()
            if re.search(r'\bd-i\b', text) or any(x in text for x in ('debian installer', 'install.amd', 'preseed', 'netinst', 'isolinux')):
                fail('legacy Debian Installer configuration: ' + relative)
    manifest = {}
    for line in (tree / 'install/appliance.img.manifest').read_text().splitlines():
        match = re.fullmatch(r'(payload_sha256|payload_size|image_sha256|image_size)=([0-9a-fA-F]+)', line)
        if not match or match[1] in manifest:
            fail('malformed or duplicate manifest entry')
        manifest[match[1]] = match[2]
    if set(manifest) != {'payload_sha256', 'payload_size', 'image_sha256', 'image_size'}:
        fail('incomplete manifest')
    for key in ('payload_sha256', 'image_sha256'):
        if not re.fullmatch('[0-9a-fA-F]{64}', manifest[key]):
            fail('malformed manifest hash: ' + key)
    for key in ('payload_size', 'image_size'):
        if not re.fullmatch(r'(0|[1-9][0-9]*)', manifest[key]) or int(manifest[key]) == 0:
            fail('malformed manifest size: ' + key)
    payload_path = tree / 'install/appliance.img.zst'
    with payload_path.open('rb') as payload_file:
        payload_hash = hashlib.file_digest(payload_file, 'sha256').hexdigest()
    if payload_hash != manifest['payload_sha256'].lower() or payload_path.stat().st_size != int(manifest['payload_size']):
        fail('payload manifest mismatch')
    raw_hash = hashlib.sha256(); raw_size = 0
    with subprocess.Popen([zstd, '-dc', str(tree / 'install/appliance.img.zst')], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as proc:
        assert proc.stdout is not None
        output = proc.stdout
        for chunk in iter(lambda: output.read(1024 * 1024), b''):
            raw_hash.update(chunk); raw_size += len(chunk)
        result = proc.wait()
    if result or raw_hash.hexdigest() != manifest['image_sha256'].lower() or raw_size != int(manifest['image_size']):
        fail('raw image manifest mismatch')
    image.close()


if __name__ == '__main__':
    if len(sys.argv) != 5:
        fail('usage: validate-iso-tree.py REPORT TREE ISO BOOT_HYBRID_IMG')
    validate(pathlib.Path(sys.argv[1]).read_text(), sys.argv[2], sys.argv[3], sys.argv[4])
    print('ISO BIOS/UEFI assets and catalog: PASS')
