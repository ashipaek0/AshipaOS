# A95X F3 Air hardware evidence

Evidence supplied by the owner of the exact unit (MANUAL, 2026-09-24).

| Fact | Value | Evidence |
|---|---|---|
| Stock firmware on eMMC | slimBOXtv ATV 9.20, build `A95X_F3_AIR_M-9.0.0-202006121521`, Android 9 | owner report (Settings) |
| RAM | 4 GB | owner report; `sm1_s905x3_4g.dtb` usable memory `0x100000..0xf0900000` |
| Ethernet | 100 Mbit, SoC internal PHY | owner report; `internal_phy = <1>` in `device-tree/sm1_s905x3_4g.dtb` |
| CoreELEC DTB that boots this unit | `device-tree/sm1_s905x3_4g.dtb`, SHA-256 `3c51d8a67b447f3f2afdcdb7ad5993f40a2e5d57cda905b43459d8b6660c48fc` | owner boots CoreELEC from SD with it as `dtb.img` |
| SD boot of CoreELEC | works | owner report; CoreELEC's `aml_autoscript` has therefore rewritten the saved U-Boot boot command (it runs `saveenv`), so the box now runs `cfgload` from SD at every power-on |
| UART | not available | owner report |

The matching mainline device tree is `amlogic/meson-sm1-a95xf3-air.dtb`
(internal RMII PHY), not the `-gbit` variant.

## First AshipaOS boot (2026-09-24, image from commit 9e53383)

Logs in `boot-2026-09-24/`, copied from the SD card by the owner.

- `ashipaos-stage2-u-boot.txt`: the vendor U-Boot chain-loaded the AshipaOS
  mainline U-Boot (`U-Boot 2024.07-g3f772959 ... ashipaos-a95x-f3-air`), which
  found the card on `mmc 0` and loaded the kernel. No stage-1 log was supplied.
- `ashipaos-stage3-linux.txt`: Debian `6.1.0-52-arm64` booted with
  `meson-sm1-a95xf3-air.dtb` (model "Shenzhen CYX Industrial Co., Ltd
  A95XF3-AIR"); meson-drm, panfrost (Mali-G31), HDMI framebuffer console,
  meson-ir, audio cards and a USB 2.4 GHz keyboard/mouse came up; the internal
  PHY bound. `end0` had no link, the clock was not set (no network, no RTC),
  and `ashipaos-jellyfin-mpv-shim.service` exited with an error about 5 s after
  each start (reason not captured by that report version).

## Second boot (2026-09-24, image from commit 085da41)

Logs in `boot-2026-09-24b/`. The chain-load and kernel boot repeated. Owner
report: boot text on HDMI, then a blinking cursor; no `ashipaos-stage1-vendor.txt`
(the vendor U-Boot cannot write FAT; stage 2 proves the chain-load); no
Ethernet cable; Wi-Fi is required.

The shim's journal shows the root cause of its restart loop:
`AttributeError: ('mpv option does not exist', ..., b'auto-window-resize', b'no')`.
Jellyfin MPV Shim 3.0.0 sets mpv 0.37+/0.38+ options unconditionally; Debian
bookworm ships libmpv 0.35.1. The image moves to Debian trixie (libmpv 0.40).
The vendor DTB's `wifi` node (`dhd_static_buf`, Broadcom DHD) and the SDIO card
on `mmc2` indicate a Broadcom Wi-Fi module; its exact chip ID is PROVISIONAL.
