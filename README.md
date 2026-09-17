# AshipaOS

AshipaOS is a purpose-built, TV-oriented OS for single-board computers and TV
boxes: it boots straight into a 10-foot Jellyfin client experience (via a
generic Jellyfin/mpv-shim application layer) with managed OS/app updates,
rollback, provisioning, and a privileged `settingsd` service for UI-driven
system operations.

## Targets

| Target | Hardware | Arch | Track | Status |
|---|---|---|---|---|
| `x86_64` | Generic x86_64 (UEFI) | x86_64 | Debian rootfs + image assembly | PROVISIONAL |
| `a95x-f3-air` | A95X F3 Air TV box | arm64 (Amlogic) | CoreELEC-based Amlogic pipeline | PROVISIONAL |

## Development builds

The `release-build` GitHub Actions workflow builds both targets and publishes
`v0.0.1-dev` as a prerelease. The x86_64 artifact is QEMU-boot tested. The
Amlogic artifact is a generic CoreELEC hardware baseline and must be tested from
removable media with a hardware-verified DTB before it is considered supported.
