# A95X boot bundle contract

Owner: image assembler (`layers/layer2-image/scripts/build-image.sh`), with
values from `layers/layer2-image/config/image-config.yaml`, the pinned
mainline U-Boot in `layers/layer2-image/config/u-boot/`, and the target's
`mainline_boot` section in `build/targets/amlogic/boxes/a95x-f3-air.yaml`.

## Boot chain

1. The box's vendor U-Boot (2015.01, on eMMC) is used as-is. The image never
   writes a bootloader, sectors 1..8191, eMMC, or the saved U-Boot environment.
2. Vendor U-Boot runs one entry script from FAT partition 1. Three names are
   shipped with the same content, for the three ways it looks at the SD card:
   `aml_autoscript` (its own recovery/reset-button path), `cfgload` (an
   environment rewritten by CoreELEC, as on the reference unit) and
   `s905_autoscript` (an Armbian-style environment). The script records
   `ashipaos-stage1-vendor.txt`, loads `u-boot.ext` to `0x01000000` and `go`es
   there.
3. `u-boot.ext` is mainline U-Boot built in CI from a pinned commit and tree
   (`build-u-boot.sh`) for `meson-sm1-a95xf3-air`. Its environment lives in RAM
   only (`ENV_IS_NOWHERE`), and DFU, USB gadget and mass-storage support are
   disabled. It shows its console on HDMI, finds the card by `ashipaos.id`,
   and runs `boot.scr`.
4. `boot.scr` records `ashipaos-stage2-u-boot.txt`, loads `Image`, the mainline
   DTB and `initrd.img`, and runs `booti`. If `booti` returns, it records
   `ashipaos-stage2-u-boot-failed.txt`.
5. Linux writes `ashipaos-stage3-linux.txt` 60 s after boot
   (`ashipaos-boot-report.service`).

## Payload relationships

| File | Source | Rule |
|---|---|---|
| `u-boot.ext` | pinned mainline U-Boot | must carry the `ashipaos-a95x-f3-air` identity and the target's mainline DTB |
| `Image` | rootfs `/vmlinuz` | decompressed to a raw arm64 Image |
| `initrd.img` | rootfs `/initrd.img` | same kernel version as `Image` |
| `meson-sm1-a95xf3-air.dtb` | rootfs `/usr/lib/linux-image-<kver>/amlogic/` | same kernel package version as `Image` |
| `manifest.json` | generated | SHA-256 of every boot file and the rootfs archive hash |

The CoreELEC vendor DTB and the stock `meson1.dtb` are 4.9-kernel device trees
and are never paired with the mainline kernel. FAT names are lower case where
vendor U-Boot reads them, because it lower-cases the requested name before
comparing it with long file names.

## Status

`mainline_boot` is `PROVISIONAL`: the chain is build-verified and its scripts
were executed in U-Boot's sandbox, but it has not yet booted on the exact unit.
The unit has no UART; the three stage logs on the SD card are the evidence path.
