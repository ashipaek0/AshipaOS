# AshipaOS A95XF3-Air

This branch is the Amlogic A95X F3 Air appliance track.

- Boot source: pinned CoreELEC/Amlogic provenance under `build/coreelec/`.
- Target: `a95x-f3-air`, arm64, removable SD media only.
- The image contract uses the validated DOS/FAT16/Android-style boot partition and ext4 root partition.
- Full image builds run in GitHub Actions only; local full image builds are not permitted.
- Never overwrite eMMC. Use 3.3 V TTL UART only; never connect UART VCC/5 V or RS-232 voltage.
- Do not add unrelated appliance targets or host-specific build paths to this branch.

All dependency pins, checksums, provenance, and no-reusable-plaintext-password requirements are mandatory.
