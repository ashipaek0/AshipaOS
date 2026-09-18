# U-Boot Bootloader for A95X F3 Air (Amlogic S905X3)

Layer 2 uses the complete stock `aml_sdc_burn.UBOOT` bundle extracted from the
provided A95X image. It is intentionally not split into BL301/BL31/U-Boot
pieces. `ddr-usb.bin` is the matching USB DDR-training payload retained for
provenance/recovery tooling and is not concatenated into the SD bundle.

`meson1.dtb` is the raw 4-GiB FDT extracted from the gzip-wrapped stock
`meson1.dtb` payload (FDT magic `d00dfeed`, 80,329 bytes).

## Required Files

The committed target inputs are:

1. **aml_sdc_burn.UBOOT** - complete stock SD U-Boot bundle
2. **ddr-usb.bin** - matching stock USB DDR payload
3. **meson1.dtb** - raw stock 4-GiB device tree

### Optional but Recommended
5. **acs.bin** - Amlogic Certificate Signature blob
   - Required for some boot modes
   - Extracted from stock firmware

6. **gxbb_g12a_hdcp_tx.bin** - HDCP firmware
   - Required for protected content playback
   - HDMI compliance

7. **smhc_normal.bin** - eMMC storage controller firmware
   - Improves eMMC reliability and performance

## Obtaining These Files

### Option 1: Mainline U-Boot (Recommended for Development)
```bash
git clone https://source.denx.de/u-boot/u-boot.git
cd u-boot
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
make aml-s905x3-cc_defconfig
make -j$(nproc)
```
Output files will be in the build directory.

### Option 2: Extract from Stock Firmware
1. Download official A95X F3 Air firmware from manufacturer
2. Extract using `unzip` or Amlogic's USB Burning Tool images
3. Use `dd` to extract partitions:
   ```bash
   dd if=stock_firmware.img of=u-boot.bin bs=1M skip=1 count=4
   ```

### Option 3: Pre-built Binaries (CI/CD)
For automated builds, these files should be:
- Stored as GitHub Secrets or in a private artifact repository
- Downloaded during the Layer 2 build process
- Verified with checksums before use

## File Placement

After obtaining the files, place them in this directory:
```
/workspace/layers/layer2-image/files/u-boot/a95x-f3-air/
├── u-boot.bin
├── bl301.bin
├── bl31.img
├── ddr4_1d.fw (or ddr3_1d.fw depending on RAM)
├── acs.bin (optional)
├── gxbb_g12a_hdcp_tx.bin (optional)
└── smhc_normal.bin (optional)
```

## Build Script Integration

The `build-image.sh` script will automatically:
1. Check for required files (u-boot.bin, bl301.bin, bl31.img)
2. Create the `u-boot.img` composite image
3. Write it to the raw sectors before the EFI partition
4. Configure the boot script for kernel loading

## Verification

After building, verify the bootloader is present:
```bash
# Check U-Boot location in image
hexdump -C ashipaos-a95x-f3-air.img | head -20

# Should show U-Boot signature at offset 0
```

## Important Notes

⚠️ **WARNING**: Using incorrect U-Boot binaries can brick your device!
- Always verify the exact hardware revision
- Match DDR firmware to your RAM type (DDR3 vs DDR4)
- Test on recoverable devices first (have USB-C TTL adapter ready)

📋 **Evidence Required**: Per AshipaOS build policy, all PROVISIONAL values must be verified with:
- Photos of serial console output
- md5sum/sha256sum of all binary blobs
- Documentation of source and extraction method

## References
- [Mainline U-Boot Amlogic Support](https://github.com/u-boot/u-boot/tree/master/board/amlogic)
- [ARM Trusted Firmware](https://github.com/ARM-software/arm-trusted-firmware)
- [LibreELEC A95X F3 Air Support](https://github.com/LibreELEC/LibreELEC.tv/tree/master/packages/u-boot)
- [AshipaOS Build Guide](../../../docs/build-guide.md)
