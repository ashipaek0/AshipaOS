# A95X storage contract

The image is for removable SD media only. eMMC must never be written.

| Region | Sectors | Contents |
|---|---|---|
| MBR | 0 | DOS partition table |
| Gap | 1..8191 | zero; no raw SD payload is written |
| Partition 1 (boot) | 8192, 256 MiB | type `0x0e`, bootable, FAT16 labelled `A95XBOOT`: `aml_autoscript`, `cfgload`, `s905_autoscript`, `u-boot.ext`, `boot.scr`, `ashipaos.id`, `active-root.txt`, `manifest.json`, `wifi.txt`, per-slot `Image-<slot>`/`initrd.img-<slot>`/`meson-sm1-a95xf3-air-<slot>.dtb`; the boot-stage logs are written here at boot |
| Partition 2 (root_a) | 532480, 2048 MiB | type `0x83`, ext4 labelled `RootFS-A`; populated at build time, the slot a fresh flash always boots |
| Partition 3 (root_b) | 4726784, 2048 MiB | type `0x83`, ext4 labelled `RootFS-B`; empty until an OS update installs into it (`contracts/os-ota.md`) |
| Partition 4 (storage) | 8921088, 512 MiB | type `0x83`, ext4 labelled `STORAGE`, mounted at `/storage`; grown to fill the rest of the SD card on first boot (`ashipaos-storage-grow.service`) |

Only one root slot is ever mounted as `/` at a time; `root=` is not fixed in
any slot's `/etc/fstab` (there is no `/` line at all) — `boot.scr` assembles
`root=LABEL=RootFS-A` or `root=LABEL=RootFS-B` on the kernel command line for
whichever slot `active-root.txt` selects, so the same rootfs image works
unmodified as either slot. See `contracts/os-ota.md` for the A/B update and
rollback contract this exists for.

Partition 1 is mounted at `/boot/firmware` (vfat, `nofail`) for the boot
report. STORAGE (partition 4) is shared by both root slots across an update
and is never wiped or resized by one: application state lives under
`/storage` (`/storage/jellyfin-mpv-shim`), owned by the `ashipa` service user
with mode `0700`, created by `systemd-tmpfiles.d` once STORAGE is mounted.
