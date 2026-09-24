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
