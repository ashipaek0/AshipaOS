# AshipaOS x86_64

This branch is the standalone x86_64 UEFI appliance track.

## Build

Canonical image builds run in GitHub Actions. The supported target is `x86_64` only.

The image uses a Debian root filesystem, systemd, UEFI/GPT partitioning, GRUB, and the Jellyfin MPV Shim application bundle.

## Validation

Static contracts, image layout checks, QEMU boot validation, SBOM generation, signing, checksums, and OTA packaging run in CI.

Physical GPU, HDMI, audio, input, and live media playback remain hardware validation gates.
