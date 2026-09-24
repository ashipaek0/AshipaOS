# A95X boot bundle contract

Owner: image assembler (`layers/layer2-image/scripts/build-image.sh`), with
values from `layers/layer2-image/config/image-config.yaml` and the target's
`mainline_boot` section in `build/targets/amlogic/boxes/a95x-f3-air.yaml`.

## Boot chain

1. The stock vendor U-Boot (2015.01) on the box's eMMC is used as-is. The
   image never writes a bootloader, sectors 1..8191, eMMC, or the saved U-Boot
   environment.
2. The vendor SD recovery path loads `aml_autoscript` from FAT partition 1. It
   resets the environment in RAM, sets load addresses, and runs `cfgload`.
3. `cfgload` sets `bootargs`, loads `dtb.img` to `dtb_mem_addr` and
   `kernel.img` to a scratch address, then runs `bootm` on it.

## Payload relationships

| File | Source | Rule |
|---|---|---|
| `kernel.img` | rootfs `/vmlinuz` + `/initrd.img` | Android legacy v0, page 2048; kernel decompressed to a raw arm64 Image and placed at `kernel_base + text_offset`; must end below `kernel_limit` |
| `dtb.img` | rootfs `/usr/lib/linux-image-<kver>/<mainline_boot.device_tree>` | must come from the same kernel package version as `kernel.img` |
| `manifest.json` | generated | SHA-256 of every boot file, load addresses, and the rootfs archive hash |

The kernel, initramfs and DTB always come from one rootfs archive; nothing is
taken from the build host. The CoreELEC vendor DTB and the stock `meson1.dtb`
are 4.9-kernel device trees and are never paired with the mainline kernel.

FAT file names are lower case: vendor U-Boot lower-cases the requested name
before comparing it with long file names.

## Status

`mainline_boot` is `PROVISIONAL`. The chain is build-verified only; UART boot
evidence on the exact unit is required before it becomes `CONFIRMED`.
