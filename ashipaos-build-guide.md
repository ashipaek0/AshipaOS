# A95X F3 Air build guide

## Scope

This branch builds only the Amlogic A95X F3 Air appliance: a Debian trixie
arm64 root filesystem that boots straight into Jellyfin MPV Shim, started from
removable SD by the box's stock vendor U-Boot, which chain-loads a pinned mainline U-Boot from the
SD card. CoreELEC provenance under `build/coreelec/` is the
evidence-backed baseline for the target.

## Pins

| Input | Pin |
|---|---|
| Jellyfin MPV Shim | commit + archive SHA-256 in `layers/layer5-application/scripts/jellyfin-bundle.py` and `build/coreelec/pin.json` |
| Python dependency closure | `layers/layer5-application/config/dependencies.lock.json` (versions, PyPI URLs, SHA-256) |
| Debian packages | snapshot.debian.org timestamp in `layers/layer1-rootfs/config/rootfs-config.yaml` (Release signatures verified with `debian-archive-keyring`); installed versions are recorded per build in `output/evidence/layer1-packages.tsv` and the SBOM |
| GitHub Actions | full commit SHAs, enforced by `tests/static/test-workflow-files.sh` |
| CoreELEC baseline | `build/coreelec/pin.json` (tag, commit, archive, Dockerfile and base-image digests) |
| Mainline U-Boot | tag, tag object, commit and tree in `layers/layer2-image/config/u-boot/pin.json`; config in `a95x-f3-air.config` |
| Stock box blobs | SHA-256 in `layers/layer2-image/files/a95x-f3-air/provenance.json` |

To move the Debian pin, change `debian.snapshot` and review the package diff
in the build evidence.

## Runtime

The appliance boots with or without a network: no unit waits for
`network-online.target` (`systemd-networkd-wait-online` is masked), and the
clock is set by `systemd-timesyncd` once a network appears.

`ashipaos-jellyfin-mpv-shim.service` runs `cage` (Wayland kiosk compositor,
via `seatd`) with the validated launcher inside it, as `ashipa`, restarting on
failure with a bounded limit; the getty on tty1 is masked. cage delivers
keyboard, mouse and remote input through libinput. On first start the launcher
seeds `/storage/jellyfin-mpv-shim/conf.json` (fullscreen library browser, no
idle quit, no GitHub update checks) and `mpv.conf` (Wayland output,
`hwdec=auto-safe`); later edits persist. `ASHIPAOS_BOOT_SUCCESS=1` on the UART
means the shim and the boot-status endpoint are still running 20 s after start.

To refresh the Python lock, run
`python3 layers/layer5-application/scripts/jellyfin-bundle.py update-lock`
and review the diff; CI rejects a lock whose closure pip cannot reproduce with
`--require-hashes`.

## Required gates

1. Static gates (`tests/static/run-static.sh`) pass, including the CoreELEC pin
   validation against the authorized fork.
2. The rootfs contains the kernel, initramfs and the mainline DTB from one
   kernel package, and no fixed machine-id.
3. The Jellyfin closure matches the lock and imports on the target interpreter.
4. The image gate confirms the MBR layout, the zero gap before sector 8192,
   the FAT16 boot files, the chain-load scripts and u-boot.ext, the kernel,
   and the root filesystem.
5. Release artefacts are checksummed, signed (tags always), and carry an SBOM.
6. Hardware testing uses removable SD only (never eMMC) and a 3.3 V TTL UART
   without VCC (never RS-232 levels).

Hardware boot, display, audio, input and playback remain hardware evidence;
they are not inferred from these static and build gates.
