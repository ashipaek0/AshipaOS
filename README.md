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
| Layer 1 rootfs | `layers/layer1-rootfs/scripts/build-rootfs.sh` | Debian bookworm arm64 rootfs (pinned snapshot) with kernel, initramfs, mainline DTB, Python 3.11, libmpv, Mesa |
| Layer 5 resolve | `layers/layer5-application/scripts/jellyfin-bundle.py resolve` | hash-verified wheels from the committed lock, import-probed on the target under qemu |
| Layer 5 install | `layers/layer5-application/scripts/build-application.sh` | Jellyfin MPV Shim bundle, launcher, and the boot service in the rootfs |
| Layer 2 image | `layers/layer2-image/scripts/build-image.sh` | 4 GiB DOS/MBR image: FAT16 boot + ext4 root |
| Image gate | `layers/layer2-image/tests/image-content-tests.sh` | read-only inspection of the built image |
| Layer 10 release | `layers/layer10-release/scripts/build-10-release.sh` | `.img.gz` and `SHA256SUMS-a95x-f3-air` |
| SBOM, signing | `scripts/ci-generate-sbom.sh`, `scripts/ci-sign-artefacts.sh` | CycloneDX SBOM, detached `.asc` signatures |

Tags `v*.*.*` build, sign and publish a release. `workflow_dispatch` builds on
demand; `allow_unsigned` permits placeholder signatures for development runs.
`pr.yml` runs the static gates on pull requests. `coreelec-ce2a.yml`
(manual) builds and inspects the pinned stock CoreELEC image as evidence.

See `ashipaos-build-guide.md` and `contracts/`.
