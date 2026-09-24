# Build a custom offline appliance-installer ISO

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept current. It follows the ExecPlan method supplied to the implementing agent.

## Purpose / Big Picture

A release build will create a complete AshipaOS appliance before installation, place that appliance in a bootable raw disk image, and embed the compressed image in a small custom installer ISO. Booting that ISO with one safe blank disk attached will install without a network interface or questions. The installer will refuse ambiguous or unsafe storage, verify bytes before and after writing, grow the final root partition, and avoid overwriting a completed appliance.

## Progress

- [x] (2026-09-23 12:54Z) Read issue 23, the branch workflow, all legacy build scripts, and relevant provisioning files.
- [x] (2026-09-23 13:20Z) Add tests that demonstrate the missing architecture and safety behavior.
- [x] (2026-09-23 13:20Z) Implement root filesystem, raw disk, custom installer runtime, and hybrid ISO builders.
- [x] (2026-09-23 13:20Z) Implement fail-closed target selection, integrity checking, expansion, completion, and reinstall protection.
- [x] (2026-09-23 13:20Z) Add executable no-network BIOS and UEFI VM harnesses and staged GitHub Actions jobs.
- [x] (2026-09-23 13:20Z) Remove the legacy installer architecture and update operator documentation.
- [x] (2026-09-23 14:10Z) Rework the rejected implementation: self-contained initramfs command/runtime closure, source ancestry and mounted-root marker guards, strict expansion, Debian trixie snapshot provisioning, offline system Flatpak installation, PARTUUID boot configuration, mandatory BIOS/UEFI ISO images, staged VM marker checks, workflow evidence uploads, and behavior-oriented safety/SSH tests.
- [x] (2026-09-23 15:00Z) Third SWE repair pass: remove payload from initramfs, add interpreter/command closure and physical storage modules, require 20 GiB VM disks, validate BIOS/UEFI boot structures, enforce offline Flathub collection/ref installation, readiness/process checks, force-aware safety policy, OpenSSH parsing, resolver/GTK dependencies, fresh OVMF VARS, workflow timeouts/checksums, and generated-key behavior tests.
- [x] (time unverified; before seventh QA at 2026-09-23 15:22Z) Fourth repair pass: shared image-size contract with margin, rootfs-identity-safe ownership, GRUB2 hybrid MBR and ISO asset validator, strict initramfs command/module closure, force marker policy, partition growth, resolver contract, VM disk hash guard, Flatpak commit lock expansion, and 22 executable behavior tests.
- [x] (time unverified; before seventh QA at 2026-09-23 15:22Z) Fifth SWE repair pass: production-only block-device and mounted partition marker validation, fixture isolation, source-medium discovery, GRUB2 rescue hybrid metadata, complete initramfs closure/negative checks, offline Flatpak graph commit verification, post-install VM guard hashing, SSH enablement, evidence provenance, and 26 executable regression tests.
- [x] (time unverified; before seventh QA at 2026-09-23 15:22Z) Sixth SWE repair pass: canonical partition helper for SATA/NVMe, immediate selector revalidation before the destructive stream, exact force-layout checks, distinct marker/unsafe refusal tokens, verified source payload discovery, initramfs rmdir/manifest closure, isolated exported Flatpak graph locks, fresh OVMF guard vars, ISO boot-image/FAT checks, evidence manifests, corrected Flatpak repo semantics, and 28 executable regression tests.
- [x] (2026-09-23 15:22Z, verified by seventh QA) Seventh SWE repair pass: copied sourced installer helpers, added source discovery and an exact Flatpak set verifier. The 33 local checks passed but seventh QA rejected several production paths and grep-only tests; the earlier 19:00Z timestamp was future-dated and is withdrawn.
- [x] (2026-09-23 18:30Z) Eighth SWE local repair: module-tree path resolution, production layout and descendant policy, post-modprobe discovery, functional offline Flatpak fallback, relational ISO inspection, force VM stage, and executable mocked regression tests. BUILD/VM/hardware evidence remains unclaimed.

## Surprises & Discoveries

- Observation: The old image builder modifies an upstream installer initramfs and performs package and Flatpak installation on the destination.
  Evidence: `scripts/build-iso.sh` patches an upstream initrd while `provision/finalize-install.sh` installs the application after destination installation.
- Observation: The initial implementation's seven tests were false-positive prone: the two-disk fixtures were below the eligibility minimum, completion checks ran only against an injected directory, and the initramfs mounted the ISO over its own payload directory.
  Evidence: QA reproduced all three defects; the repaired fixtures use 20 GB disks, production install mounts partition 3, and the ISO now mounts at `/run/iso` while the runtime stays at `/installer`.
- Observation: A safe install target must be both blank and ancestry-distinct from the ISO; rejecting only removable/read-only/loop devices is insufficient.
  Evidence: selector behavior now rejects sysfs child partitions and resolves `sda1`, `nvme0n1p3`, and `mmcblk0p3` ancestry.

## Decision Log

- Decision: Build all release layers with explicit scripts and keep local verification limited to static and unit tests.
  Rationale: Full root filesystem, disk image, ISO, and virtual-machine runs require privileged Linux tooling and are canonical only in GitHub Actions.
  Date/Author: 2026-09-23 / Hermes SWE
- Decision: Test storage policy through a synthetic sysfs/dev fixture accepted by the same selector used in the installer.
  Rationale: This gives deterministic destructive-safety coverage without attaching real disks or requiring root.
  Date/Author: 2026-09-23 / Hermes SWE
- Decision: Treat an occupied disk as ineligible before installation, even when it lacks an AshipaOS marker.
  Rationale: A completion marker is not a proof that arbitrary existing data is disposable; fail-closed selection is safer.
  Date/Author: 2026-09-23 / Hermes SWE
- Decision: Build initramfs runtime closure from resolved host commands plus their dynamic libraries and Debian kernel modules, and load storage/ISO/ext4 modules before selection.
  Rationale: Copying only BusyBox cannot execute the bash installer or its integrity/expansion pipeline.
  Date/Author: 2026-09-23 / Hermes SWE
- Decision: Keep the compressed appliance and manifest only on the ISO `/install` tree; initramfs contains scripts and runtime closure, then mounts the ISO at `/run/iso`.
  Rationale: This bounds installer memory/storage and keeps the 2 GiB VM viable.
  Date/Author: 2026-09-23 / Hermes SWE
- Decision: Require a real OpenSSH parse in addition to one-line/type/base64 validation.
  Rationale: Shape-only keys can still be unusable credentials.
- Decision: Permit force selection only after reading `/var/lib/ashipaos/install-complete` from target partition 3 read-only; synthetic roots require an explicit fixture flag and can never reach destructive installation.
  Rationale: An environment variable or generic occupied-disk bypass cannot prove that existing data is an AshipaOS installation.
- Decision: Treat the installed-disk hash captured after successful installation and boot as the sole guard baseline.
  Rationale: Comparing guard output with the pre-install hash would incorrectly report the legitimate installation write as a guard mutation.
- Decision: Lock every installed Flatpak ref and commit and install from `create-usb`'s `.ostree/repo` inside a network namespace.
  Rationale: A top-level app lock does not protect runtimes/extensions, and a configured remote must not silently fetch missing objects.
- Decision: Use a GPT image with a BIOS boot partition, FAT32 EFI System Partition, and final ext4 root partition, then install both GRUB targets in the prebuilt image.
  Rationale: The final root partition can be expanded in place while supporting legacy firmware and the standard removable-media UEFI fallback path.
  Date/Author: 2026-09-23 / Hermes SWE

## Outcomes & Retrospective

The local implementation now contains the custom offline installer, image/ISO pipeline, CI stages, and safety tests. Local BUILD and VM evidence remain unclaimed until GitHub Actions executes the corresponding jobs on one commit; hardware validation is outside this software pass.

## Context and Orientation

The repository currently has one workflow at `.github/workflows/build-iso.yml`. The replacement pipeline uses `scripts/build-rootfs.sh` to create the complete Debian 13 filesystem, `scripts/assemble-disk-image.sh` to put it into a bootable raw disk, `scripts/build-installer-initramfs.sh` to create a dedicated installation runtime, and `scripts/build-iso.sh` to combine the runtime and compressed appliance image. `installer/select-target.sh` owns destination safety policy and `installer/install.sh` performs the destructive write only after selection and integrity checks. A manifest is a small text file containing checksums and byte counts. A PARTUUID is the stable identifier stored in a GPT partition table and used by the installed boot configuration.

`tests/run.sh` is the local canonical test entrypoint. It runs syntax and architecture checks plus behavior tests against temporary fake block-device trees. `scripts/vm-test.sh` is a CI-only harness: it installs with the virtual network interface disabled, then boots only the installed disk and waits for an appliance-ready serial marker.

## Plan of Work

First create tests for forbidden legacy artifacts, SSH key validation, storage selection, corrupt image manifests, unsafe explicit destinations, and the completed-install guard. Observe that they fail because the replacement scripts do not exist. Then add common shell helpers and implement the selector and installer around injectable directory roots so tests exercise production logic without real block devices.

Next create the complete image pipeline. The root filesystem builder will use `mmdebstrap` in GitHub Actions, install every required package, copy appliance configuration, create locked accounts, install the Flatpak payload into the system installation, enable services, and clear machine-specific identity and host keys before sealing. The disk builder will create the fixed GPT layout, populate ext4, install BIOS and UEFI GRUB, and emit a PARTUUID-based configuration. The initramfs and ISO builders will create their outputs in temporary paths and rename only after success.

Finally replace the workflow with STATIC, BUILD, VM BIOS, and VM UEFI jobs. BUILD uploads the ISO and checksums; both VM jobs download that exact artifact and run with no emulated NIC. Update the README with build boundaries, secret format, artifacts, disk safety, and honest evidence gates.

## Concrete Steps

From `/home/ubuntu/AshipaOS`, run:

    tests/run.sh

The initial test run must fail because required installer files are absent. After implementation, the command must report every unit/static test passed without building an image.

Canonical release validation runs only through `.github/workflows/build-iso.yml`. Its BUILD job runs the root filesystem, raw image, custom initramfs, and ISO scripts. Its VM jobs invoke:

    sudo scripts/vm-test.sh bios out/ashipaos-installer.iso
    sudo scripts/vm-test.sh uefi out/ashipaos-installer.iso

Each VM run must have no NIC, observe installation completion on the serial console, boot the installed disk, and observe `ASHIPAOS_BOOT_OK`. A timeout or absent marker is a failure rather than synthetic success.

## Validation and Acceptance

Local acceptance requires `tests/run.sh`, `git diff --check`, and shell syntax checks to pass. Tests must prove zero and multiple eligible disks are rejected; optical, removable, read-only, loop, RAM, undersized, and installation-source devices are excluded; a valid explicit target is accepted while a wrong or unsafe one is rejected; malformed, missing, and multiline SSH keys are rejected; a corrupt payload is rejected before writing; and a completion marker blocks a normal reinstall.

BUILD acceptance requires nonempty appliance root, raw image, compressed image, manifest, initramfs, and hybrid ISO artifacts. ISO inspection must show the custom kernel, initramfs, compressed appliance, manifest, and both firmware boot paths, with no legacy installer content. VM acceptance is separate for SeaBIOS and OVMF. Hardware remains blocked until a person tests target hardware.

## Idempotence and Recovery

Build scripts use temporary directories, cleanup traps, and final atomic renames. Re-running them replaces only outputs under `out/`. The installer does not write when selection or verification fails. Once the completion marker exists on a destination root filesystem, normal execution hands off to that system instead of rewriting it; an explicit force kernel argument is required to reinstall.

## Artifacts and Notes

The release artifact names are `out/ashipaos-installer.iso`, `out/ashipaos-installer.iso.sha256`, `out/appliance.img.zst`, `out/appliance.img.manifest`, and `out/flatpak-lock.json`. Logs from BUILD and both VM firmware jobs are evidence only for the exact workflow commit that produced them.

## Interfaces and Dependencies

Every new shell script starts with `#!/usr/bin/env bash` and `set -Eeuo pipefail`. `installer/select-target.sh` exports or prints exactly one canonical `/dev/<disk>` path and returns nonzero for every ambiguous or unsafe state. It accepts `ashipaos.install_target=` only as an exact device name or canonical device path after validating it against the same policy as automatic selection.

`installer/install.sh` reads `ashipaos.force=1` as the sole reinstall override. It verifies SHA-256 and size values from `appliance.img.manifest`, streams `appliance.img.zst` to the selected whole disk, hashes exactly the raw image byte count back from that disk, expands partition 3 and its ext4 filesystem, writes `/var/lib/ashipaos/install-complete` last, synchronizes, and reboots or powers off for the VM test mode.

CI dependencies include `mmdebstrap`, `debootstrap`, `parted`, `gdisk`, `dosfstools`, `e2fsprogs`, `grub-pc-bin`, `grub-efi-amd64-bin`, `grub-common`, `xorriso`, `zstd`, `qemu-system-x86`, `qemu-utils`, `ovmf`, `flatpak`, and `ostree`.

Revision note: initial plan created from issue 23 and the current branch before implementation.