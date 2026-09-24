# AshipaOS A95X F3 Air

Appliance image for the Amlogic S905X3 A95X F3 Air that boots straight into
Jellyfin MPV Shim, fullscreen on HDMI (`ashipaos-jellyfin-mpv-shim.service`).

Target: `a95x-f3-air` · Architecture: `arm64` · Media: removable SD only.

Full builds run in GitHub Actions only. Never overwrite eMMC. Use a 3.3 V TTL
UART only: never connect UART VCC/5 V, never use RS-232 levels.

## Pipeline (`.github/workflows/build-images.yml`)

| Step | Script | Output |
|---|---|---|
| Static gates | `tests/static/run-static.sh` | pass/fail for every contract test |
| Layer 1 rootfs | `layers/layer1-rootfs/scripts/build-rootfs.sh` | Debian trixie arm64 rootfs (pinned snapshot) with kernel, initramfs, mainline DTB, Python 3.13, libmpv 0.40, Mesa, Wi-Fi |
| Layer 5 resolve | `layers/layer5-application/scripts/jellyfin-bundle.py resolve` | hash-verified wheels from the committed lock, import-probed on the target under qemu |
| Layer 5 install | `layers/layer5-application/scripts/build-application.sh` | Jellyfin MPV Shim bundle, launcher, and the boot service in the rootfs |
| U-Boot | `layers/layer2-image/scripts/build-u-boot.sh` | pinned mainline U-Boot (`u-boot.ext`), chain-loaded by the vendor U-Boot |
| Layer 2 image | `layers/layer2-image/scripts/build-image.sh` | 4 GiB DOS/MBR image: FAT16 boot + ext4 root |
| Image gate | `layers/layer2-image/tests/image-content-tests.sh` | read-only inspection of the built image |
| Layer 10 release | `layers/layer10-release/scripts/build-10-release.sh` | `.img.gz` and `SHA256SUMS-a95x-f3-air` |
| SBOM, signing | `scripts/ci-generate-sbom.sh`, `scripts/ci-sign-artefacts.sh` | CycloneDX SBOM, detached `.asc` signatures |

Tags `v*.*.*` build, sign and publish a release. `workflow_dispatch` builds on
demand; `allow_unsigned` permits placeholder signatures for development runs.
`pr.yml` runs the static gates on pull requests. `coreelec-ce2a.yml`
(manual) builds and inspects the pinned stock CoreELEC image as evidence.

See `ashipaos-build-guide.md` and `contracts/`.

## Wi-Fi

Before the first boot (or any time later), open the SD card's `A95XBOOT`
partition on a PC and fill in `wifi.txt`:

```
SSID=MyNetwork
PASSWORD=my-wifi-password
```

On boot the password is converted to the WPA key hash, stored only on the box
(`/var/lib/iwd`, root-only), and removed from `wifi.txt`. The box also boots
and starts the app without any network.

## Diagnosing a boot without a UART

After a boot attempt, put the SD card in a PC and open its `A95XBOOT` partition:

| File | Written by | Means |
|---|---|---|
| `ashipaos-stage1-vendor.txt` | box's vendor U-Boot | the SD entry script ran (which one, and the saved boot command) |
| `ashipaos-stage2-u-boot.txt` | AshipaOS mainline U-Boot | the chain-load worked; kernel arguments and load addresses |
| `ashipaos-stage2-u-boot-failed.txt` | AshipaOS mainline U-Boot | `booti` refused the kernel |
| `ashipaos-stage3-linux.txt` | Linux, 60 s after boot | failed units, Jellyfin MPV Shim status, kernel log |

Delete them before the next attempt so stale logs are not mistaken for new
ones. Mainline U-Boot also prints its console on HDMI.
