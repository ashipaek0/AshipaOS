# Ownership contract (build guide §1.1)

Every generated artefact has a declared owner. No component may silently
take ownership of another component's state. A local developer machine is
not an authoritative build or release environment.

| Area | Owner |
|---|---|
| Filesystem contents | Rootfs construction |
| Target-specific parameters | Target definitions (`build/targets/`) |
| Partition tables, filesystems, final image assembly | Image assembler |
| Kernel/initramfs/DTB/bootloader relationships | Boot bundle contract |
| Update state and activation | Updater |
| Writable application payload only | Application updater |
| First-run network configuration | Provisioning |
| Privileged operations exposed to the UI | `settingsd` |
| Box-specific values | Target/box configuration (`build/targets/amlogic/boxes/`) |
| Canonical build execution | CI |
| Hardware evidence | Hardware lab |
| Release publication and checksums | Release automation |

Detailed interface contracts: `boot-bundle.md`, `storage.md`,
`settingsd.md`, `os-ota.md`, `app-ota.md`, `provisioning.md`, `release.md`.
