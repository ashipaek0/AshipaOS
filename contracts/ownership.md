# Ownership contract

Every generated artefact has a declared owner. No component may silently take
ownership of another component's state. A local developer machine is not an
authoritative build or release environment.

| Area | Owner |
|---|---|
| Root filesystem contents | Layer 1 (`layers/layer1-rootfs`) |
| Application bundle and launcher | Layer 5 (`layers/layer5-application`) |
| Partition table, filesystems, boot files, image assembly | Layer 2 (`layers/layer2-image`) |
| Kernel/initramfs/DTB/bootloader relationships | `boot-bundle.md` |
| Writable application payload and slot selection | `app-ota.md` |
| Box-specific values | `build/targets/amlogic/boxes/` |
| CoreELEC baseline provenance | `build/coreelec/`, `coreelec-integration.md` |
| Canonical build execution | GitHub Actions |
| Hardware evidence | Hardware lab (`hardware-lab/`, `hardware-facts.md`) |
| Release publication, checksums, signatures, SBOM | Layer 10 and `scripts/ci-*.sh` |

Detailed interface contracts: `boot-bundle.md`, `storage.md`, `app-ota.md`,
`coreelec-integration.md`, `hardware-facts.md`.
