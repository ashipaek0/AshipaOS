# A95X storage contract

The image is for removable SD media only. eMMC must never be written.

| Region | Sectors | Contents |
|---|---|---|
| MBR | 0 | DOS partition table |
| Gap | 1..8191 | zero; no raw SD payload is written |
| Partition 1 | 8192, 256 MiB | type `0x0e`, bootable, FAT16 labelled `A95XBOOT`: `aml_autoscript`, `cfgload`, `kernel.img`, `dtb.img`, `manifest.json` |
| Partition 2 | 532480, 3584 MiB | type `0x83`, ext4 labelled `RootFS`, mounted at `/` |

Application state lives under `/storage` on the root filesystem
(`/storage/jellyfin-mpv-shim`, `/storage/apps/jellyfin-mpv-shim/slots`), owned
by the `ashipa` service user with mode `0700`.
