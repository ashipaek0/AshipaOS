# AshipaOS x86_64 Branch Rules

This branch is strictly the x86_64 UEFI appliance track.

- Keep only x86_64 target files, build logic, tests, documentation, and CI jobs.
- Do not add other target platforms, boot formats, or architecture-specific assets.
- Full image builds run only in GitHub Actions.
- Local validation is limited to static checks, contract tests, and read-only inspection.
- Validate generated image layout, QEMU boot, signing, SBOM, checksums, and OTA artifacts.
- Do not claim physical hardware behavior from static or QEMU evidence.
- Do not embed reusable plaintext credentials.
