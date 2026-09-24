#!/usr/bin/env python3
"""Small El Torito report/tree fixtures, independent of xorriso availability."""
import hashlib
import importlib.util
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'scripts/validate-iso-tree.py'
spec = importlib.util.spec_from_file_location('iso_tree', SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class IsoRelations(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.tree = self.base / 'tree'
        self.iso = self.base / 'fixture.iso'
        # Synthetic GRUB hybrid-MBR template; xorriso patches bytes 432..435.
        self.boot_hybrid = self.base / 'boot_hybrid.img'
        self.boot_code = bytes((i * 37 + 11) % 256 for i in range(440))
        self.boot_hybrid.write_bytes(self.boot_code + bytes(72))
        self.report = '''El Torito catalog  : 40  1
El Torito cat path : /boot.catalog
El Torito images   :   N  Pltf  B   Emul  Ld_seg  Hdpt  Ldsiz         LBA
El Torito boot img :   1  BIOS  y   none  0x0000  0x00      4          41
El Torito boot img :   2  UEFI  y   none  0x0000  0x00    832          42
El Torito img path :   1  /boot/grub/i386-pc/eltorito.img
El Torito img path :   2  /efi.img
'''
        files = {
            'boot/vmlinuz': b'kernel', 'boot/initramfs.gz': b'initramfs',
            'boot/grub/grub.cfg': b'menuentry install {\n linux /boot/vmlinuz quiet\n initrd /boot/initramfs.gz\n}\nmenuentry force {\n linux /boot/vmlinuz quiet ashipaos.force=1\n initrd /boot/initramfs.gz\n}\n',
            'boot/grub/i386-pc/eltorito.img': b'GRUB',
            'EFI/BOOT/BOOTX64.EFI': b'efi',
        }
        for path, content in files.items():
            asset = self.tree / path
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_bytes(content)
        fat = self.tree / 'efi.img'
        subprocess.run(['truncate', '-s', '16M', str(fat)], check=True)
        subprocess.run(['mkfs.vfat', str(fat)], stdout=subprocess.DEVNULL, check=True)
        subprocess.run(['mmd', '-i', str(fat), '::EFI', '::EFI/BOOT'], check=True)
        subprocess.run(['mcopy', '-i', str(fat), str(self.tree / 'EFI/BOOT/BOOTX64.EFI'), '::EFI/BOOT/BOOTX64.EFI'], check=True)
        payload = self.tree / 'install/appliance.img.zst'
        payload.parent.mkdir(parents=True)
        self.raw = b'raw image'
        subprocess.run(['zstd', '-q', '-f', '-o', str(payload)], input=self.raw, check=True)
        self.manifest = payload.parent / 'appliance.img.manifest'
        self.manifest.write_text('\n'.join([
            f'image_sha256={hashlib.sha256(self.raw).hexdigest()}', f'image_size={len(self.raw)}',
            f'payload_sha256={hashlib.sha256(payload.read_bytes()).hexdigest()}', f'payload_size={payload.stat().st_size}',
        ]) + '\n')
        catalog = bytearray(2048)
        catalog[0] = 1
        catalog[30:32] = b'\x55\xaa'
        (self.tree / 'boot.catalog').write_bytes(catalog)
        with self.iso.open('wb') as out:
            out.truncate(42 * 2048 + fat.stat().st_size)
        with self.iso.open('r+b') as out:
            out.write(self.boot_code)
            # Plausible hybrid MBR fixture: one Linux partition record and
            # standard signature. This does not demonstrate machine boot.
            out.seek(446)
            out.write(bytes([0, 0, 2, 0, 0x83, 0, 2, 0]) + (1).to_bytes(4, 'little') + (100).to_bytes(4, 'little'))
            out.seek(510)
            out.write(b'\x55\xaa')
            for lba, path in [(40, 'boot.catalog'), (41, 'boot/grub/i386-pc/eltorito.img'), (42, 'efi.img')]:
                out.seek(lba * 2048)
                out.write((self.tree / path).read_bytes())

    def valid(self):
        validator.validate(self.report, self.tree, self.iso, self.boot_hybrid)

    def bad(self):
        with self.assertRaises(SystemExit):
            self.valid()

    def test_positive(self):
        self.valid()

    def test_zero_filled_system_area_is_rejected(self):
        with self.iso.open('r+b') as out:
            out.write(bytes(32768))
        self.bad()

    def test_missing_mbr_signature_is_rejected(self):
        with self.iso.open('r+b') as out:
            out.seek(510); out.write(b'\x00\x00')
        self.bad()

    def test_zeroed_bootstrap_only_is_rejected(self):
        with self.iso.open('r+b') as out:
            out.seek(0); out.write(bytes(440))
        self.bad()

    def test_non_grub_bootstrap_is_rejected(self):
        with self.iso.open('r+b') as out:
            out.seek(10); out.write(b'not-grub')
        self.bad()

    def test_missing_mbr_partition_record_is_rejected(self):
        with self.iso.open('r+b') as out:
            out.seek(446); out.write(bytes(64))
        self.bad()

    def test_wrong_catalog_path(self):
        self.report = self.report.replace('/boot.catalog', '/other.catalog')
        self.bad()

    def test_wrong_platform(self):
        self.report = self.report.replace('2  UEFI', '2  PPC ')
        self.bad()

    def test_wrong_lba(self):
        self.report = self.report.replace('832          42', '832          43')
        self.bad()

    def test_wrong_image_path(self):
        self.report = self.report.replace('/efi.img', '/other/efi.img')
        self.bad()

    def test_missing_fat_fallback(self):
        subprocess.run(['mdel', '-i', str(self.tree / 'efi.img'), '::EFI/BOOT/BOOTX64.EFI'], check=True)
        # Update the ISO's catalog-referenced image to match, so FAT contents are tested.
        with self.iso.open('r+b') as out:
            out.seek(42 * 2048)
            out.write((self.tree / 'efi.img').read_bytes())
        self.bad()

    def test_missing_initrd(self):
        (self.tree / 'boot/grub/grub.cfg').write_text('linux /boot/vmlinuz\n')
        self.bad()

    def test_force_menu_missing_initrd(self):
        config = self.tree / 'boot/grub/grub.cfg'
        config.write_text(config.read_text().rsplit(' initrd /boot/initramfs.gz\n', 1)[0] + '}\n')
        self.bad()

    def test_duplicate_manifest(self):
        with self.manifest.open('a') as out:
            out.write('image_size=9\n')
        self.bad()

    def test_wrong_image_metadata(self):
        self.manifest.write_text(self.manifest.read_text().replace('image_size=9', 'image_size=8'))
        self.bad()

    def test_legacy_asset(self):
        (self.tree / 'install.amd').mkdir()
        self.bad()

    def test_legacy_config(self):
        (self.tree / 'boot/grub/extra.cfg').write_text('d-i debian-installer/locale string en_US\n')
        self.bad()


if __name__ == '__main__':
    unittest.main(verbosity=2)
