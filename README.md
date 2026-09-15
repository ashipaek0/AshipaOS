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
