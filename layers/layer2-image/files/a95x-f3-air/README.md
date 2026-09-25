# A95X F3 Air stock inputs

Stock files extracted from the provided A95X F3 Air Android image. Their
SHA-256 values are recorded in `provenance.json` and checked by
`layers/layer2-image/tests/static-tests.sh`.

| File | What it is | Used by the SD image |
|---|---|---|
| `aml_sdc_burn.UBOOT` | Complete stock SD U-Boot bundle (vendor U-Boot 2015.01) | No |
| `ddr-usb.bin` | Matching stock USB DDR-training payload | No |
| `meson1.dtb` | Raw stock vendor 4.9 FDT (`amlogic-dt-id` `sm1_ac213_2g`), 80,329 bytes | No |

None of these are written to the image; they are kept for provenance and
recovery only. The image never writes sectors 1..8191 or any eMMC data
partition. The one deliberate exception is a single, guarded write to the
vendor U-Boot's own saved environment on the first boot, so later boots do
not need the recovery button; see `contracts/boot-bundle.md`.

The image boots through the vendor U-Boot already on the box: an SD entry
script (`aml_autoscript`, `cfgload` or `s905_autoscript`) chain-loads the
pinned mainline U-Boot (`u-boot.ext`), which boots Debian's mainline kernel,
initramfs and the mainline DTB shipped by the same kernel package
(`build/targets/amlogic/boxes/a95x-f3-air.yaml`, `mainline_boot`). The stock
`meson1.dtb` cannot be used for that kernel.

Physical boot is unverified. Test only from removable SD. The reference unit has
no UART: read the `ashipaos-stage*.txt` logs from the SD card instead.
