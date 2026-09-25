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
4. `boot.scr` reads `active-root.txt` (`active_root`, `pending`, `boot_tries`).
   If a boot is `pending`, it counts this attempt; at `max_boot_tries` (see
   `image-config.yaml`) it flips `active_root` to the other slot and clears
   `pending`/`boot_tries`, writing the result back to `active-root.txt` before
   ever loading a kernel. See `contracts/os-ota.md` for the full update and
   rollback contract this exists for. It then records
   `ashipaos-stage2-u-boot.txt`, loads that slot's `Image-<slot>`, mainline DTB
   and `initrd.img-<slot>`, assembles `root=LABEL=<RootFS-A|RootFS-B>` onto
   `bootargs`, and runs `booti`. If `booti` returns, it records
   `ashipaos-stage2-u-boot-failed.txt`.
5. Linux writes `ashipaos-stage3-linux.txt` 60 s after boot
   (`ashipaos-boot-report.service`).

## Payload relationships

| File | Source | Rule |
|---|---|---|
| `u-boot.ext` | pinned mainline U-Boot | must carry the `ashipaos-a95x-f3-air` identity and the target's mainline DTB |
| `active-root.txt` | generated (`a`/`0`/`0` on a fresh flash) | the only mutable boot-partition state; rewritten solely by `boot.scr`'s U-Boot logic, never by Linux |
| `Image-a` / `Image-b` | slot rootfs `/vmlinuz` | decompressed to a raw arm64 Image; slot B's files exist only once an OS update has installed into it |
| `initrd.img-a` / `initrd.img-b` | slot rootfs `/initrd.img` | same kernel version as the matching `Image-<slot>` |
| `meson-sm1-a95xf3-air-a.dtb` / `-b.dtb` | slot rootfs `/usr/lib/linux-image-<kver>/amlogic/` | same kernel package version as the matching `Image-<slot>` |
| `manifest.json` | generated | format `ashipaos-a95x-boot-v4`; SHA-256 of every fixed boot file (not `active-root.txt`, which changes at runtime) and the rootfs archive hash; records both root slots and the STORAGE partition |

The CoreELEC vendor DTB and the stock `meson1.dtb` are 4.9-kernel device trees
and are never paired with the mainline kernel. FAT names are lower case where
vendor U-Boot reads them, because it lower-cases the requested name before
comparing it with long file names.

## Status

`mainline_boot` is `CONFIRMED` to Linux userspace on the exact unit (see
`build/targets/amlogic/boxes/a95x-f3-air.yaml` and
`evidence/amlogic/a95x-f3-air/`): the chain-load, `boot.scr` and `booti` of the
single-slot layout were exercised on real hardware before the A/B slot
mechanism was introduced. The A/B slot selection and revert logic in
`boot.scr` is build- and sandbox-verified (a real cross-compiled U-Boot build
executing the generated script) but not yet re-confirmed on the exact unit.
The unit has no UART; the SD card's stage logs and `active-root.txt` are the
evidence path.
