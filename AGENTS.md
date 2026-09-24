# AshipaOS A95XF3-Air

This branch is the Amlogic A95X F3 Air appliance track: an SD-card image that
boots straight into Jellyfin MPV Shim, fullscreen on HDMI.

- Target: `a95x-f3-air` (S905X3), arm64, removable SD media only.
- Unit: 4 GB RAM, 100 Mbit internal-PHY Ethernet, slimBOXtv ATV 9.20
  (Android 9) on eMMC, no UART; see `evidence/amlogic/a95x-f3-air/`.
- Image: Debian bookworm arm64 pinned to a snapshot.debian.org timestamp
  (`layers/layer1-rootfs/config/rootfs-config.yaml`), with Debian's mainline
  kernel, its initramfs, and the mainline `meson-sm1-a95xf3-air.dtb` (internal
  PHY) from the same kernel package.
- Boot: the box's vendor U-Boot runs an SD entry script (`aml_autoscript`,
  `cfgload` or `s905_autoscript`), which chain-loads a pinned mainline U-Boot
  (`u-boot.ext`, RAM-only environment), which runs `boot.scr` → `booti`. Each
  stage writes a log to the SD card's FAT partition (no-UART diagnostics). The
  image contract is the DOS/MBR layout with a FAT16 boot partition at sector
  8192 and an ext4 root partition at sector 532480; see
  `contracts/boot-bundle.md` and `contracts/storage.md`.
- Application: Jellyfin MPV Shim is installed from a hash-pinned lock
  (`layers/layer5-application/config/dependencies.lock.json`) and started at
  boot by `ashipaos-jellyfin-mpv-shim.service` (user `ashipa`, tty1, DRM/KMS).
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
