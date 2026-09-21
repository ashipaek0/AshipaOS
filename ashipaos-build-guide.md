# AshipaOS x86_64 Build Guide

This branch produces only the x86_64 UEFI image.

## Pipeline

1. Layer 1 builds the Debian amd64 root filesystem.
2. The display layer installs the Wayland/DRM and Cage runtime.
3. The service and application layers install systemd policy and the pinned Jellyfin MPV Shim bundle.
4. The image layer creates the GPT/vFAT/ext4 disk image and GRUB EFI boot path.
5. The release layer generates OTA metadata, SBOM, signatures, and checksums.

The canonical full build is GitHub Actions. Local work is limited to static tests and contract checks; do not run a local full image build.

## Acceptance

A successful CI run must pass static contracts, generated-image inspection, QEMU boot, signing, SBOM, checksum, and artifact-upload gates. Physical display and playback require separate hardware validation.
