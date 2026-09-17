# Layer 1: Minimal Debian Root Filesystem

Layer 1 creates a reproducible Debian rootfs for `x86_64`/`amd64`, `arm64`,
and `armhf`. The kernel and initramfs are Debian packages installed inside
the target rootfs; host `/boot` is never read or copied.

## Verification class

**BUILD** — requires debootstrap, package-mirror access, and (for a cross-arch
build) qemu-user-static. Static tests do not claim that a rootfs boots.

## Usage

```bash
./scripts/build-rootfs.sh <target_arch> <output_file>
./scripts/build-rootfs.sh x86_64 output/rootfs-x86_64.tar.gz
./scripts/build-rootfs.sh amd64 output/rootfs-amd64.tar.gz
./scripts/build-rootfs.sh arm64 output/rootfs-arm64.tar.gz
./scripts/build-rootfs.sh armhf output/rootfs-armhf.tar.gz
```

`x86_64` is explicitly mapped to Debian `amd64`. ARM architectures remain
configured for rootfs builds, but this Layer 1 change does **not** claim ARM VM
support or physical hardware support.

## Kernel/initramfs policy

`config/rootfs-config.yaml` is the policy source for supported architectures.
The builder installs the target kernel package and `initramfs-tools` with apt
inside the target rootfs. For both native and debootstrap `--foreign` builds it
then runs `update-initramfs -u -k all` in the target chroot. The build fails
non-zero unless all of these are true:

- `/boot/vmlinuz` is non-empty and resolves to a non-empty versioned
  `/boot/vmlinuz-*` file;
- `/boot/initrd.img` is non-empty and resolves to a non-empty versioned
  `/boot/initrd.img-*` file;
- the configured kernel and initramfs packages are installed and have resolved
  versions.

Layer 1 evidence records the mapped architecture, package names and versions,
resolved file paths, sizes, SHA-256 hashes, and output tarball metadata.

## Requirements

- bash 4+
- debootstrap
- mount (the build mounts target `/proc`, `/sys`, and `/dev` only while
  installing packages)
- qemu-user-static for cross-architecture builds
- network access to the declared Debian mirror

## Static tests

```bash
./tests/static-tests.sh
```

The static suite covers shell syntax, explicit `x86_64 → amd64` mapping,
package/initramfs policy, evidence metadata hooks, no host `/boot` copy path,
and non-zero missing-argument/invalid-architecture paths. It does not run
Debian debootstrap, install packages, or boot a VM.

## Explicit non-goals for Stage 1

- No QEMU VM workflow or boot claim.
- No ARM VM or physical-hardware support claim.
- No host-kernel or host-`/boot` fallback.
- No mutable, undeclared kernel download or copied workstation artefact.
- No image partitioning, bootloader integration, or Layer 2 userspace work.

## Outputs

- Root filesystem tarball (`.tar.gz`)
- JSON build evidence under `evidence/`
