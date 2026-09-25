# AshipaOS A95XF3-Air

This branch is the Amlogic A95X F3 Air appliance track: an SD-card image that
boots straight into Jellyfin MPV Shim, fullscreen on HDMI.

- Target: `a95x-f3-air` (S905X3), arm64, removable SD media only.
- Unit: 4 GB RAM, 100 Mbit internal-PHY Ethernet, slimBOXtv ATV 9.20
  (Android 9) on eMMC, no UART; see `evidence/amlogic/a95x-f3-air/`.
- Image: Debian trixie (13) arm64 pinned to a snapshot.debian.org timestamp
  (`layers/layer1-rootfs/config/rootfs-config.yaml`), with Debian's mainline
  kernel, its initramfs, and the mainline `meson-sm1-a95xf3-air.dtb` (internal
  PHY) from the same kernel package.
- Boot: the box's vendor U-Boot runs an SD entry script (`aml_autoscript`,
  `cfgload` or `s905_autoscript`), which chain-loads a pinned mainline U-Boot
  (`u-boot.ext`, RAM-only environment), which runs `boot.scr` → `booti`.
  `boot.scr` also picks the active A/B root slot from `active-root.txt` and
  reverts to the other slot after repeated failed boots, entirely inside
  U-Boot. Each stage writes a log to the SD card's FAT partition (no-UART
  diagnostics). The image contract is the DOS/MBR layout with a FAT16 boot
  partition at sector 8192, two ext4 root slots (A/B) at sectors 532480 and
  4726784, and an ext4 STORAGE partition at sector 8921088; see
  `contracts/boot-bundle.md`, `contracts/storage.md` and `contracts/os-ota.md`.
- Application: Jellyfin MPV Shim is installed from a hash-pinned lock
  (`layers/layer5-application/config/dependencies.lock.json`) and started at
  boot by `ashipaos-jellyfin-mpv-shim.service` (user `ashipa`) inside the `cage`
  Wayland kiosk compositor on `seatd`, which delivers keyboard/mouse/remote
  input. Wi-Fi is a Realtek RTL8822CS (`firmware-realtek`), configured from
  `wifi.txt` on the boot partition.
- CoreELEC: `build/coreelec/` pins and inspects the stock CoreELEC baseline as
  hardware-fact evidence only; nothing from it is copied into the image.
- Full image builds run in GitHub Actions only; local full image builds are not
  permitted. `tests/static/run-static.sh` is the single static gate.
- Never overwrite eMMC and never write the saved U-Boot environment. Use 3.3 V
  TTL UART only; never connect UART VCC/5 V or RS-232 voltage.
- Do not add unrelated appliance targets or host-specific build paths to this
  branch.

All dependency pins, checksums, provenance, and no-reusable-plaintext-password
requirements are mandatory.
