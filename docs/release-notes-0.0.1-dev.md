# AshipaOS 0.0.1-dev

This is an engineering development prerelease, not a production release.

## Artifacts

- **x86_64:** Debian Bookworm GPT/UEFI image, validated structurally and booted
  with QEMU in CI.
- **A95X F3 Air / Amlogic:** CoreELEC `Amlogic-ng` generic baseline image with
  the AshipaOS development identity package. The exact DTB is intentionally not
  preselected because hardware evidence is not yet available.

## Important limitations

- Amlogic hardware verification is blocked pending a physical device, selected
  DTB, and serial-console evidence.
- The Amlogic baseline retains Kodi; replacement with the final AshipaOS
  Jellyfin experience follows successful stock hardware validation.
- The x86_64 image does not yet include the final Jellyfin application payload,
  provisioning, settings daemon, or OTA rollback implementation.

Verify every downloaded artifact against its accompanying SHA-256 data before
flashing it. Use removable test media; do not install the Amlogic image to eMMC.
