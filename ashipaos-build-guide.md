# AshipaOS Build Guide

## Refactored Implementation Contract with GitHub/CI Execution Model

**Status:** Refactored build guide  
**Purpose:** Autonomous-agent-friendly implementation and verification plan  
**Execution model:** GitHub is the source of truth, GitHub Actions is the canonical build/test system for remotely verifiable work, and physical hardware is treated as a separate remotely controlled test infrastructure where available.

---

# 0. How to use this guide

AshipaOS is built incrementally.

Each task has:

- Goal
- Scope
- Inputs
- Outputs
- Implementation
- Invariants
- Verification
- Evidence
- Runner

Do not begin a dependent task until its prerequisites pass.

The repository and its CI state are the source of truth.

A coding agent **MUST NOT** invent:

- hardware behaviour;
- package names;
- device-tree names;
- service names;
- kernel capabilities;
- bootloader behaviour;
- target-specific values;

when the repository or an explicit verification task does not establish them.

---

## 0.1 Verification classes

Every verification step has a **class**.

| Class | Meaning |
|---|---|
| `STATIC` | Can be verified by inspecting files, schemas, scripts, or configuration without building |
| `BUILD` | Requires executing the build pipeline or producing an artefact |
| `VM` | Requires booting the resulting image in a virtual machine |
| `HARDWARE` | Requires the actual target hardware |
| `MANUAL` | Requires human observation or physical interaction |

A task is complete only when every required verification for that task passes.

---

## 0.2 Verification runners

The verification **class** describes what kind of proof is required.

The **runner** describes where that proof is obtained.

| Runner | Meaning |
|---|---|
| `github-actions` | Executed in the canonical CI environment |
| `hardware-lab` | Executed on real hardware controlled by a remote test runner |
| `human` | Executed by a person, with recorded evidence |
| `blocked` | Required runner unavailable; task must not be marked complete |

Verification must declare both class and runner.

Example:

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: pi5

  - class: MANUAL
    runner: human
    reason: IR remote behaviour observed physically
```

A task that requires `HARDWARE` or `MANUAL` verification cannot be completed purely on GitHub unless the project provides remote access to the actual hardware.

If no hardware runner exists, the task is **blocked**, not passed.

---

## 0.3 Evidence contract

Every passed verification must produce evidence.

Evidence may include:

- command output;
- build logs;
- CI job logs;
- image checksums;
- serial console logs;
- screenshots;
- video recordings;
- test reports;
- hardware inventory records;
- release manifests;
- SBOM output.

Evidence must be retained as CI artefacts or in the repository evidence archive.

A hardware fact without evidence is not a confirmed fact.

---

# 0.4 Canonical execution model

AshipaOS is designed around the following separation from the beginning:

> **GitHub and CI prove that the software and image are internally correct.**  
> **Remote hardware proves that the physical target behaves correctly.**

GitHub-connected coding agents can implement and verify a large part of the system remotely.

Physical hardware verification cannot be completed purely on GitHub unless the project has remote access to real hardware.

---

## 0.5 What can be done entirely remotely

The following can be implemented and verified through GitHub and CI:

| Area | Remote GitHub/CI |
|---|---|
| Repository structure | ✅ |
| Layer 0–10 implementation | ✅ |
| Debian rootfs | ✅ |
| Pi image construction | ✅ |
| x86_64 image construction | ✅ |
| Kernel/toolchain builds | ✅ |
| Image partitioning | ✅ |
| systemd services | ✅ |
| settingsd | ✅ |
| OTA checker | ✅ |
| OTA updater | ✅ |
| App updater | ✅ |
| Rollback logic | ✅ |
| Provisioning software | ✅ |
| Firewall configuration | ✅ |
| Static tests | ✅ |
| Build tests | ✅ |
| VM tests | ✅ |
| Release artefacts | ✅ |
| Release manifests/checksums | ✅ |
| Documentation | ✅ |
| GitHub releases | ✅ |

GitHub Actions is the authoritative build environment.

A developer workstation is not the authoritative builder.

This directly prevents the earlier x86_64 defect where the image could accidentally depend on the host machine’s installed kernel.

---

## 0.6 What GitHub cannot prove by itself

GitHub cannot prove physical hardware behaviour.

The following require actual hardware:

- Does the image boot on a Pi 4?
- Does it boot on a Pi 5?
- Does an AshipaOS image built from the pinned `ashipaek0/CoreELEC` fork still boot the exact A95X F3 Air with the confirmed DTB installed as `dtb.img`?
- Does the no-Kodi service reach the released Jellyfin MPV Shim full-screen library/browser UI?
- Do the retained CoreELEC display, audio, Ethernet, Wi-Fi, Bluetooth where exercised, storage, and claimed input paths still work after replacement integration?
- Does Jellyfin MPV Shim, rather than Kodi, select the expected hardware decoder for each claimed codec, including 10-bit HEVC?
- Does the physical provisioning process work?
- Does a real TV display the expected output?
- Does the remote control behave correctly?
- Does OTA rollback actually recover the physical device after a failed boot?

The pinned stock image, confirmed DTB, display/video, Wi-Fi, Bluetooth, and general box hardware are already confirmed baseline facts for the user's exact unit. They must not be reopened as unknown merely because GitHub cannot reproduce physical evidence. The questions above concern the AshipaOS post-replacement integration and remain independent `HARDWARE`/`MANUAL` gates; stock-baseline success cannot pass them.

These require either:

- an automated remote hardware lab; or
- manual human testing with recorded evidence.

---

## 0.7 Target workflow

The intended development workflow is:

```text
Issue
  ↓
Coding agent
  ↓
Branch
  ↓
Pull request
  ↓
Automated static/build/VM tests
  ↓
Hardware tests where available
  ↓
Human review
  ↓
Merge
  ↓
Signed release
```

A coding agent does not declare a task finished by assertion.

CI and, where required, hardware evidence declare the task finished.

---

## 0.8 CI architecture

The repository should use this high-level model:

```text
GitHub repository
       │
       ├── Pull Request
       │       │
       │       ├── static tests
       │       ├── unit tests
       │       ├── build tests
       │       └── VM boot tests
       │
       ├── merge
       │
       └── GitHub Actions
               │
               ├── build Pi 4 image
               ├── build Pi 5 image
               ├── build x86_64 image
               ├── build Amlogic image
               ├── validate images
               ├── generate manifests
               └── publish release candidate
```

Then separately:

```text
                    GitHub
                       │
                 release/image
                       │
              ┌────────┴────────┐
              │                 │
           CI tests        Remote hardware
                              │
                    ┌─────────┼─────────┐
                    │         │         │
                  Pi 4      Pi 5     A95X
                    │         │         │
                    └─────────┼─────────┘
                              │
                       hardware tests
                              │
                       results → GitHub
```

---

## 0.9 Remote hardware lab

Where possible, AshipaOS should support a remote hardware lab.

Example:

```text
hardware lab
│
├── Pi 4
│   ├── network-controlled power
│   ├── serial console
│   ├── boot media
│   └── test network
│
├── Pi 5
│   ├── network-controlled power
│   ├── serial console
│   └── boot media
│
└── A95X F3 Air
    ├── network-controlled power
    ├── UART/serial console
    └── removable boot media
```

The hardware workflow should be:

```text
build image
     ↓
publish candidate
     ↓
hardware test runner
     ↓
flash/test device
     ↓
power cycle
     ↓
capture serial output
     ↓
run automated tests
     ↓
collect logs
     ↓
report result to GitHub
```

Some tests remain inherently observational, for example:

- physical IR remote usability;
- TV picture quality;
- HDMI/CEC interaction with a specific television;
- user-visible remote-control behaviour.

Those remain `MANUAL` unless the lab has the required capture equipment.

---

# 1. Non-negotiable engineering contracts

These rules apply to the entire repository.

---

## 1.1 Repository, CI, and ownership

Every generated artefact must have a declared owner.

- Rootfs construction owns filesystem contents.
- Target definitions own target-specific parameters.
- The image assembler owns partition tables, filesystems, and final image assembly.
- The boot bundle contract owns kernel/initramfs/DTB/bootloader relationships.
- The updater owns update state and activation.
- The application updater owns only the writable application payload.
- Provisioning owns first-run network configuration.
- `settingsd` owns privileged operations exposed to the UI.
- Hardware-specific configuration belongs under the appropriate target/box configuration.
- CI owns canonical build execution.
- The hardware lab owns hardware evidence.
- Release automation owns release publication and checksums.

No component may silently take ownership of another component’s state.

A local developer machine is not an authoritative build or release environment.

---

## 1.2 Build reproducibility

A release build **MUST NOT** depend on:

- the host machine’s installed kernel;
- unrecorded host Python packages;
- mutable upstream branches;
- the current date unless explicitly supplied as a reproducible build input;
- files outside the declared source/build inputs;
- manually copied artefacts from a developer’s workstation;
- an unpinned CI runner environment where reproducibility matters.

All release inputs must be pinned or explicitly recorded.

The canonical build environment should be one of:

- a pinned GitHub-hosted runner image; or
- a pinned self-hosted runner; or
- a pinned container image used by CI.

For release builds, record:

- container image digest, if used;
- runner label;
- toolchain versions;
- package repository snapshot;
- source commits;
- build inputs manifest;
- output checksums.

---

## 1.3 Shell standard

New Bash scripts **MUST** use:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
```

Resource-allocating scripts **MUST** install cleanup traps.

Temporary files **MUST** be created using `mktemp` where appropriate.

Files that are consumed by another process **MUST** be written atomically where practical:

```text
temporary file → fsync/sync where required → rename
```

A failure **MUST** leave the system in a recoverable state.

---

## 1.4 Target isolation

A generic package **MUST NOT** contain target-specific conditionals unless the package genuinely implements a target-specific capability.

Target-specific values belong in target configuration.

Amlogic box-specific values belong in:

```text
build/targets/amlogic/boxes/
```

They **MUST NOT** be hard-coded into:

- the generic AshipaOS application package;
- the common service overlay;
- the updater;
- provisioning;
- settingsd.

---

## 1.5 Hardware fact status and evidence

Hardware facts **MUST** be labelled:

- `CONFIRMED`: directly verified on the target or from authoritative project/device documentation adopted by the repository.
- `PROVISIONAL`: plausible but not yet verified.
- `UNKNOWN`: not established.

`PROVISIONAL` and `UNKNOWN` values **MUST NOT** become silent architectural dependencies.

Hardware facts must include evidence.

Example:

```yaml
wifi:
  driver: null
  status: UNKNOWN
  evidence: []
```

After testing:

```yaml
wifi:
  driver: <driver-name>
  status: CONFIRMED
  evidence:
    - type: command
      command: iw dev
      artifact: evidence/amlogic/a95x-f3-air/wifi/iw-dev.log
    - type: network-test
      artifact: evidence/amlogic/a95x-f3-air/wifi/dhcp.log
```

For `a95x-f3-air`, the user-confirmed CoreELEC 21.3-Omega facts in Task 0.5.1 are `CONFIRMED`. Store baseline and replacement evidence under separate namespaces or status fields, such as `coreelec_baseline` and `ashipaos_integration`; integration failure must not overwrite baseline status, and baseline success must not masquerade as integration proof.

A future CoreELEC rebase triggers Task 0.5.1's trimmed reconfirmation. It does not retroactively make the current 21.3-Omega facts provisional. Other hardware facts should be reviewed when any of the following change:

- kernel branch;
- CoreELEC ref;
- device tree;
- firmware;
- box configuration;
- rootfs base;
- driver package set.

---

## 1.6 Verification evidence contract

A verification result is not valid unless it records:

- task ID;
- verification class;
- runner;
- target, where applicable;
- pass/fail/blocked state;
- evidence artefact;
- timestamp;
- commit SHA;
- CI job ID, where applicable.

Example:

```yaml
verification_result:
  task: layer3.display-service
  class: HARDWARE
  runner: hardware-lab
  target: pi5
  result: passed
  commit: <full-commit>
  job: github-actions-run-12345
  evidence:
    - serial.log
    - systemctl-status-ashipaos-display.log
    - display-photo.jpg
```

---

## 1.7 Secrets, signing, and credentials

The repository must not contain:

- WiFi credentials;
- SSH private keys;
- release signing private keys;
- Jellyfin tokens;
- hardware lab credentials;
- API secrets.

Secrets belong in:

- GitHub Actions secrets;
- hardware lab secret storage;
- release key management infrastructure.

For OTA:

- SHA-256 proves integrity.
- A signature proves authenticity.

The current guide may ship with integrity-only OTA if explicitly documented, but the manifest schema should already support future signatures.

---

## 1.8 Persistent identity and time

AshipaOS must define:

- machine identity generation;
- hostname policy;
- persistent machine-id;
- client device ID for Jellyfin;
- time synchronization behaviour.

The device must not depend on a correct RTC where hardware does not provide one.

Time synchronization must be handled before relying on TLS certificate validation or update manifests.

---

# 2. Repository contract

The repository is expanded enough to make ownership, CI, and evidence explicit.

Recommended structure:

```text
ashipaos/
 ├── .github/
 │   └── workflows/
 │       ├── pr.yml
 │       ├── build-images.yml
 │       ├── release.yml
 │       └── hardware-dispatch.yml
 │
 ├── build/
 │   ├── scripts/
 │   ├── config/
 │   │   ├── release.yaml
 │   │   └── packages.lock
 │   ├── rootfs/
 │   ├── work/
 │   └── output/
 │
 ├── build/targets/
 │   ├── pi4/
 │   ├── pi5/
 │   ├── x86_64/
 │   └── amlogic/
 │       ├── platform.yaml
 │       └── boxes/
 │           └── a95x-f3-air.yaml
 │
 ├── ci/
 │   ├── containers/
 │   ├── scripts/
 │   └── runners/
 │
 ├── contracts/
 │   ├── ownership.md
 │   ├── boot-bundle.md
 │   ├── storage.md
 │   ├── settingsd.md
 │   ├── os-ota.md
 │   ├── app-ota.md
 │   ├── provisioning.md
 │   ├── hardware-facts.md
 │   └── release.md
 │
 ├── schemas/
 │   ├── target.schema.json
 │   ├── box.schema.json
 │   ├── release-manifest.schema.json
 │   ├── app-manifest.schema.json
 │   ├── settingsd.schema.json
 │   └── hardware-facts.schema.json
 │
 ├── rootfs-overlay/
 │   ├── etc/
 │   ├── usr/
 │   └── ...
 │
 ├── packages/
 ├── provisioning/
 ├── settingsd/
 ├── updater/
 ├── imager/
 ├── tests/
 │   ├── static/
 │   ├── build/
 │   ├── vm/
 │   ├── hardware/
 │   └── negative/
 │
 ├── hardware-lab/
 │   ├── inventory.yaml
 │   ├── runners/
 │   ├── power/
 │   ├── serial/
 │   ├── flashing/
 │   └── tests/
 │
 ├── evidence/
 └── docs/
```

The canonical CoreELEC fork is the external repository `ashipaek0/CoreELEC`, fetched only from an AshipaOS-owned immutable pin record containing repository, upstream source branch, tag, full commit, fork commit, actual project/device/architecture tuple, and expected source/archive hashes. A manually populated local checkout is never authoritative.

AshipaOS-owned CoreELEC patches, package definitions, overlays, CI glue, integration contracts, and manifests remain distinct from the fetched source tree. The fork owns the A95X OS image. The application updater owns only writable application slots and must never mutate the CoreELEC system image.

The exact directory names may be adapted to the existing repository, but ownership boundaries **MUST** remain.

---

# LAYER 0 — Canonical Builder Environment

---

## Task 0.1 — Establish the canonical build environment

### Goal

A known Linux build environment capable of producing the Debian Pi/x86_64 images and supporting the separate Amlogic pipeline.

The authoritative build environment is CI.

Local developer environments are optional and non-authoritative.

### Requirements

One of:

- Ubuntu 24.04 LTS GitHub-hosted runner;
- pinned self-hosted runner;
- pinned build container used by GitHub Actions.

Minimum capabilities:

- at least 16 GB RAM, or equivalent CI capacity;
- at least 100 GB free build storage;
- x86_64 host preferred for Debian cross-build;
- internet access to explicitly pinned source repositories;
- ARM64 emulation or ARM64 runner where required.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Record:

```bash
uname -m
uname -a
df -h
```

Record host/toolchain versions in the CI build log.

---

## Task 0.2 — Install build dependencies

Install the tools required by the current pipeline, including:

- debootstrap
- qemu-user-static
- binfmt-support
- squashfs-tools
- dosfstools
- parted
- python3
- python3-pip
- git
- curl
- wget
- fdisk
- kpartx
- rsync
- xz-utils
- zstd
- openssh-client

Do not use `pip3 install --break-system-packages` merely to make an uncontrolled host environment work.

Build-time Python dependencies that affect artefacts **MUST** be pinned and installed into the declared build environment.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Examples:

```bash
mksquashfs -version
debootstrap --version
python3 --version
git --version
```

---

## Task 0.3 — Enable ARM64 emulation

Enable `binfmt_misc` and verify ARM64 execution where the runner is x86_64.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Examples:

```bash
ls /proc/sys/fs/binfmt_misc/ | grep aarch64
```

If containers are used:

```bash
docker run --rm --platform linux/arm64 ubuntu:24.04 uname -m
```

Expected output:

```text
aarch64
```

---

## Task 0.4 — Establish repository state

Create the repository structure and commit the initial skeleton.

### Invariants

- `build/rootfs/`, `build/work/`, and `build/output/` are generated directories and are not source-controlled.
- Target configuration is source-controlled.
- Versioned build inputs are source-controlled.
- CI workflow files are source-controlled.
- Schemas and contracts are source-controlled.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

Examples:

```bash
git status
git ls-files
```

---

## Task 0.5 — Establish CI workflow skeleton

### Goal

Create the base GitHub Actions workflows.

Required workflows:

- pull request validation;
- static tests;
- build tests;
- VM tests where possible;
- image validation;
- release candidate generation;
- hardware dispatch where a hardware lab exists.

### Invariants

- PR checks must not require physical hardware by default.
- Release checks must require hardware evidence where applicable.
- CI must upload evidence artefacts.
- CI must fail cleanly if loop devices or mounts are left behind.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions
```

A trivial PR must run static and build checks successfully.

---

# LAYER 0.5 — Amlogic/CoreELEC Track

The `a95x-f3-air` target is a CoreELEC-derived pipeline, not a Debian image variant. CoreELEC owns the A95X OS image and remains the boot, kernel, firmware, driver, display, decode, network, and hardware-support base. Layer 1's `debootstrap`, Debian rootfs, kernel, partition, and image-assembly path is exclusively for Pi and x86_64.

The A95X product delta is deliberately narrow:

- retain the proven pinned CoreELEC hardware and OS stack;
- exclude Kodi from the package graph before image construction, with no Kodi fallback;
- add Jellyfin MPV Shim, the smallest pinned-source-supported runtime bridge, and AshipaOS services;
- provide independently releasable, CI-built, signed A/B application bundles.

Later layers still define shared product, security, persistence, and verification outcomes for A95X where relevant. Their Debian package-install, rootfs-construction, compositor, partition, boot, and `.old` SquashFS instructions do not automatically apply. A95X implements those outcomes through CoreELEC packages and overlays, the contracts established here, and A95X-specific verification. Other A95X revisions, other S905X3 boxes, other Amlogic families, and a hypothetical second-box exercise are non-goals.

---

## Task 0.5.1 — Record the confirmed A95X/CoreELEC baseline

Here are the confirmed facts:

- The supported unit is the user's exact **A95X F3 Air** with an **Amlogic S905X3** SoC.
- The working baseline is `CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic`.
- The authoritative upstream source line is `https://github.com/CoreELEC/CoreELEC/tree/coreelec-21`.
- Tag `21.3-Omega` resolves to full commit `fc61125e8900ab0c2593a29b615980ed0cd5b939`.
- The canonical AshipaOS CoreELEC fork is `ashipaek0/CoreELEC`.
- The confirmed DTB is `sm1_s905x3_4g_1gbit.dtb`; copy it to the FAT boot-partition root and rename it `dtb.img`.
- On this exact unit, the pinned stock CoreELEC baseline confirms boot, display/video, Wi-Fi, Bluetooth, and general box hardware operation.

These are `CONFIRMED` `coreelec_baseline` facts. They are not evidence that an AshipaOS image still boots or that Jellyfin MPV Shim correctly uses the retained display, input, audio, network, or hardware-decode paths after Kodi is excluded. Those are separate `ashipaos_integration` gates in Tasks 0.5.8 and 0.5.9.

Work begins from this baseline. Do not require a stock-image rebuild, DTB discovery, serial-console availability, driver discovery, or another baseline confirmation first.

For a future CoreELEC rebase only, perform this trimmed reconfirmation:

1. Write the candidate image to spare removable media.
2. Copy `sm1_s905x3_4g_1gbit.dtb` to the FAT root as `dtb.img`.
3. Boot the user's exact box by the confirmed baseline process.
4. Capture candidate release, immutable source/fork pins, and DTB identity.
5. Smoke-test baseline boot, display/video, audio, Ethernet, Wi-Fi, Bluetooth where exercised, input, and storage behavior.
6. Compare results with the recorded 21.3-Omega baseline.

A failed candidate blocks that rebase and leaves the current 21.3-Omega pin supported; it does not invalidate the current confirmed baseline.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: baseline record contains the exact immutable inputs and separate evidence namespaces
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    when: future-rebase-only
    proves: candidate baseline reconfirmation on the exact unit
```

Evidence records the full commit, target, image, DTB/hash, timestamp, runner, results, and artefact paths. An unavailable future hardware runner is `BLOCKED`; it does not reopen the current facts.

---

## Task 0.5.2 — Pin and build the canonical CoreELEC fork

Use or create `ashipaek0/CoreELEC` from the upstream `coreelec-21` source line. Release builds fetch this canonical fork and verify both the exact tag and full commit. The initial release pin is tag `21.3-Omega` at `fc61125e8900ab0c2593a29b615980ed0cd5b939`. An AshipaOS-owned immutable pin record must contain repository, upstream source branch, tag, full upstream commit, fork commit, actual CoreELEC project/device/architecture tuple, and expected source/archive hashes.

Release preparation must fail closed when the tag resolves to another commit, the checkout is dirty, a mutable branch tip is supplied as a release input, or an expected hash differs. Read the project/device/architecture tuple from the pinned source and build output; do not infer `arm64` from the S905X3 CPU because the confirmed image is `Amlogic-ng.arm`.

CE-2A is a prerequisite-only GitHub Actions source-build and Generic-image inspection gate. It is isolated from the Debian x86_64/Pi workflows and does not select runtime, launcher, hwdec, or no-Kodi behavior. Its stock Generic output is expected to contain Kodi and is labeled `stock-kodi-containing/rejected_for_ashipaos`; evidence must report `runtime_status=UNRESOLVED`. Tasks 0.5.3–0.5.9 remain separate follow-on decisions and cannot be marked complete from CE-2A evidence.

Build the unmodified pinned fork in canonical CI as a source-build and reproducibility gate, not to rediscover hardware support. Record the source pin, fork pin, build environment/container and toolchain identities, command/tuple, output name and hashes, package graph, and complete logs.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: immutable pin format and fail-closed validation
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: clean pinned fork builds and emits recorded artefacts
```

Negative tests cover a moved tag, wrong full commit, dirty checkout, mutable branch input, wrong archive hash, and unexpected build tuple.

---

## Task 0.5.3 — Define the no-Kodi package graph

Inspect the pinned source to identify every Kodi package, dependency, image inclusion point, service, launcher, autostart path, update/recovery reference, and fallback. Exclude Kodi before image construction; never install it and delete it from a completed root filesystem. Run a dependency-closure check so no retained package silently pulls Kodi back in.

The final package manifest and image must contain no Kodi executable, package payload, Kodi-only library, add-on, configuration, unit, launcher, autostart path, update payload, recovery path, or fallback. Any retained component formerly reached through Kodi must be justified as a non-Kodi runtime dependency in the integration contract.

A removal-only image is not a release candidate and does not create a separate hardware milestone. After this package-graph gate passes, proceed directly to runtime and replacement integration.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: explicit exclusion and dependency-closure rules cover every inclusion path
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: final manifest and unpacked image contain no forbidden Kodi artefact
```

Publish the dependency graph, exclusion report, final package manifest, image scan, and logs. Any Kodi match fails the gate.

---

## Task 0.5.4 — Discover and preserve the CoreELEC media runtime

Inventory the pinned CoreELEC display, EGL/GBM/DRM, audio, input, ffmpeg, mpv/libmpv, Python ABI, hardware-decode, network, permissions, and service-manager interfaces that remain usable without Kodi. Determine whether Jellyfin MPV Shim can use direct GBM/DRM, an existing CoreELEC mpv/libmpv path, or a minimal added bridge.

Evaluate direct GBM/DRM first. Add cage or Wayland only when pinned-source, build, and exact-target evidence proves it necessary and compatible with the retained decode path. Do not choose a launcher or `hwdec` value by analogy with Pi/x86_64.

Record in the CoreELEC integration contract:

- chosen runtime bridge and rejected alternatives with evidence;
- exact packages, patches, and build flags;
- display, audio, input, network, and hardware-decode interfaces;
- device permissions and least-privilege user/group model;
- startup dependencies and environment;
- CoreELEC Python, libmpv/mpv, ffmpeg, libc, and other native ABI requirements.

Do not replace the working CoreELEC kernel, firmware, DTB, graphics, audio, network, or decode stack merely to resemble the Debian track. This task is a prerequisite for Tasks 0.5.5 and 0.5.6; later tasks may not guess its launcher, package, ABI, or hardware-decode result.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: pinned-source inventory and evidence-backed runtime decision are complete
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: selected bridge and ABI probes build against the pinned graph
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    proves: selected local runtime renders and preserves the intended media path
```

Hardware unavailability is `BLOCKED`, not permission to select cage, Wayland, direct DRM, or `hwdec` by assumption.

---

## Task 0.5.5 — Build the reproducible Jellyfin MPV Shim bundle

Use `https://github.com/jellyfin/jellyfin-mpv-shim` and pin the initial upstream stable release `v3.0.0`, published 2026-09-08. Record its resolved full commit and source archive checksum. Read requirements from that pinned release's `pyproject` and project metadata and resolve exact dependencies in CI for the CoreELEC Python and native ABI recorded by Task 0.5.4. Do not maintain a hand-authored substitute dependency list.

Produce a complete, target-compatible AshipaOS bundle containing the application and resolved Python dependencies, plus an SBOM or dependency manifest. Declare CoreELEC-provided native components, including libmpv where selected, as explicit compatibility requirements in the signed bundle manifest. Keep all A95X box-specific values outside generic application source and payload.

Production devices must not run `pip`, compile source, resolve dependencies, check out Git, query PyPI as a trust root, or install unsigned upstream payloads. They consume only AshipaOS CI-built, promoted, signed and hashed bundles.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: upstream pin, metadata-derived lock, manifest, and target isolation are complete
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: imports, entrypoint, version, configuration loading, archive safety, dependency closure, ABI metadata, reproducibility metadata, hash, and signature
```

Evidence includes upstream tag/commit/source hash, dependency-lock hash, SBOM, target/ABI contract, bundle hash, signature/key ID, build identity, and test logs.

---

## Task 0.5.6 — Integrate the A95X boot-to-Jellyfin service

Add only the package/overlay and service required by the pinned CoreELEC source and Task 0.5.4's runtime decision. At boot, launch the released upstream Jellyfin MPV Shim built-in library/browser UI full-screen and keep playback in the same appliance session. There is no visible Kodi, general-purpose desktop, or Kodi fallback.

The service must:

- run unprivileged wherever the retained CoreELEC interfaces permit, with only documented devices/groups and explicit justification for unavoidable privilege;
- load configuration, Jellyfin credentials, identity, cache, downloads, logs, and updater state from protected persistent locations under `/storage`, outside OS and application bundles;
- select a valid writable application slot when present and otherwise use the immutable known-good application bundled with the OS;
- define startup ordering, bounded restart policy, log path, application-level readiness signal, and an on-screen or remotely diagnosable failure state;
- use only upstream mainline/released built-in UI behavior.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: service, persistence, privilege, slot-selection, rescue, and no-Kodi contracts
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: required service/overlay and rescue bundle are present and internally valid
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    proves: boot reaches the full-screen released UI through the selected bridge
  - class: MANUAL
    runner: human
    target: a95x-f3-air
    proves: visible appliance UX and diagnosable failure state
```

---

## Task 0.5.7 — Build and inspect the final A95X image

Build through the pinned canonical fork in CI with the no-Kodi graph, selected runtime bridge, AshipaOS service, immutable `v3.0.0` rescue bundle, and confirmed DTB selection. Inspect the produced image and final package manifest rather than trusting build-log intent.

The gate requires:

- `sm1_s905x3_4g_1gbit.dtb` installed at the FAT root as `dtb.img`, with identity/hash checked;
- expected runtime, service, rescue bundle, and release metadata files;
- no Kodi artefact described in Task 0.5.3;
- CoreELEC tag/commit, fork commit, app tag/commit, dependency-lock hash, bundle hash/signature, image hash, and CI run recorded.

Fail on an unexpected target ABI, missing or wrong DTB, unsigned bundle/manifest, mutable input, omitted metadata, or any Kodi artefact.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: all release inputs and inspection rules are immutable and explicit
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: final image content, package graph, DTB, bundle, metadata, hashes, and signatures pass
```

Only a passing candidate proceeds to hardware dispatch.

---

## Task 0.5.8 — Verify post-Kodi A95X integration

On the user's exact A95X F3 Air, verify that the AshipaOS candidate boots with `sm1_s905x3_4g_1gbit.dtb` installed as `dtb.img` and reaches the full-screen Jellyfin library/browser without Kodi. Verify display, audio, Ethernet, Wi-Fi, Bluetooth where exercised, persistent storage, claimed input paths, and every other CoreELEC hardware behavior relied on by AshipaOS after the package/service replacement.

These are post-replacement integration regressions, not rediscovery of baseline support. Verify persistent configuration across reboot and client registration/login to a Jellyfin server without recording credentials in evidence. Record image hash, CoreELEC and fork commits, app/bundle version, exact unit/target, timestamp, runner, logs, and observational evidence.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    proves: post-Kodi boot, retained hardware paths, persistence, and server integration
  - class: MANUAL
    runner: human
    target: a95x-f3-air
    proves: full-screen UI, navigation, and visible failure-free behavior
```

Unavailable exact-box hardware is `BLOCKED`; stock CoreELEC baseline evidence cannot substitute for this gate.

---

## Task 0.5.9 — Verify Jellyfin playback and hardware decoding

Play representative H.264, HEVC, HEVC 10-bit, and every other codec claimed by the candidate through Jellyfin MPV Shim, not Kodi. For each case record:

- exact Jellyfin MPV Shim and mpv/libmpv versions and configuration;
- selected decoder and video-output path;
- codec, profile, bit depth, and resolution;
- CPU utilization, dropped frames, and playback result;
- relevant application, mpv, and kernel errors.

Use the confirmed stock CoreELEC result only for diagnosis. Kodi decoding the same file does not confirm AshipaOS integration, and smooth playback alone does not prove hardware decoding. Only codecs with captured decoder evidence may be advertised as AshipaOS capabilities.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    proves: Jellyfin playback uses the claimed hardware decoder and retained output path
  - class: MANUAL
    runner: human
    target: a95x-f3-air
    proves: visible playback quality for the declared cases
```

---

## Task 0.5.10 — Maintain and rebase the CoreELEC fork

Track stable CoreELEC tags deliberately; never feed the mutable `coreelec-21` branch head directly into a release. For a proposed rebase:

1. create a new immutable pin and retain the previous supported pin;
2. review/reapply the small AshipaOS package and overlay delta;
3. rebuild and repeat Task 0.5.3's no-Kodi closure and Task 0.5.7's image-content checks;
4. run Task 0.5.1's trimmed future-rebase baseline reconfirmation;
5. run Tasks 0.5.8 and 0.5.9;
6. independently exercise applicable OS update/recovery gates before promotion.

Record upstream changes to package conventions, Python/native ABI, mpv/libmpv, ffmpeg, graphics/decode, service manager, networking, update mechanism, DTB, firmware, and drivers. Explain upstream branch scope versus exact-box scope; never generalize this unit's DTB or evidence to another box or revision.

Do not promote a candidate until every required `STATIC`, `BUILD`, `HARDWARE`, and `MANUAL` gate passes. A failed or blocked candidate leaves the current pin and recovery path supported. CoreELEC/OS rebases remain separate in source, cadence, manifest, activation, health, and rollback from stable Jellyfin MPV Shim bundle releases.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: immutable rebase record, delta review, and change-impact inventory
  - class: BUILD
    runner: github-actions
    target: a95x-f3-air
    proves: candidate source build, no-Kodi graph, and final image inspection
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
    proves: baseline reconfirmation, post-replacement integration, decode, and recovery
  - class: MANUAL
    runner: human
    target: a95x-f3-air
    proves: visible UI, navigation, and playback acceptance
```

---

# LAYER 1 — Minimal Debian Root Filesystem

This layer builds the Debian Pi/x86_64 pipeline. No Layer 1 Debian rootfs, kernel, or image-assembly task applies to `a95x-f3-air`; A95X implementers must use Layer 0.5 and must never feed a Debian rootfs into the CoreELEC track.

---

## Task 1.1 — Bootstrap Debian

Build a minimal Bookworm root filesystem for the requested architecture.

The architecture **MUST** be an explicit build input.

Examples:

```text
amd64 → x86_64
arm64 → Pi 4 / Pi 5
```

Use `debootstrap` appropriately for native and foreign architectures.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

The rootfs contains a functioning `/bin/bash`.

---

## Task 1.2 — Configure repositories and package policy

Configure Debian repositories explicitly.

Do not allow package sources to drift silently.

Record package versions used by the release build.

For reproducibility, use one or more of:

- pinned Debian snapshot;
- pinned mirror;
- explicit apt preferences;
- generated `packages.lock`.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Example:

```bash
apt-cache policy <important-package>
```

The CI build log records the selected versions.

---

## Task 1.3 — Create the AshipaOS user

Create the non-root `ashipaos` user and required groups.

The user **MUST** own the UI process and **MUST NOT** be granted unrestricted administrative privileges.

At this layer, verification must not depend on the display stack.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Verify:

- `ashipaos` user exists;
- required groups exist;
- home/runtime paths have correct ownership;
- no unintended sudo or root privileges are granted.

The later display service task verifies that the display process runs as `ashipaos`.

---

## Task 1.4 — Define persistent storage

The logical storage contract is:

```text
/storage/
├── config/
├── state/
├── cache/
├── downloads/
├── thumbnails/
├── logs/
└── app/
```

The physical partition layout is target-specific.

The image builder **MUST NOT** assume that `/storage` is the root filesystem.

The storage contract should define:

- mountpoint;
- filesystem label or target-specific identifier;
- filesystem type;
- ownership;
- permissions;
- minimum size;
- layout version;
- migration policy;
- behaviour when missing;
- behaviour when corrupt;
- behaviour when full;
- factory reset policy.

Example contract:

```yaml
storage:
  mountpoint: /storage
  label: ashipaos-storage
  filesystem: ext4-or-target-specific
  layout_version: 1
  directories:
    config:
      owner: ashipaos
      mode: "0700"
    state:
      owner: ashipaos
      mode: "0700"
    cache:
      owner: ashipaos
      mode: "0755"
      purge_policy: safe-to-delete
    logs:
      owner: ashipaos
      mode: "0755"
      rotation: size-based
    app:
      owner: ashipaos-app-updater
      slots:
        - current
        - previous
        - pending
```

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions
```

The rootfs contract contains the expected `/storage` mountpoint and directory expectations.

Actual partition creation is verified by the image assembly task.

---

## Task 1.5 — Build target kernels properly

### Pi

Build or consume a pinned Pi kernel/firmware set appropriate to the target.

### x86_64

This task replaces the previous “copy the kernel from the build machine” instruction.

The build **MUST** select a declared x86_64 kernel package or build artefact from a pinned source.

It **MUST NOT** do:

```bash
cp /boot/vmlinuz-* ...
```

from the host machine.

The kernel version and package/source commit **MUST** be recorded in the release metadata.

### Boot bundle contract

A target must declare its boot bundle.

Conceptual example:

```yaml
boot_bundle:
  kernel:
    source: pinned-package-or-artifact
    version: <version>
  initramfs:
    required: true/false
  device_tree:
    source: target-or-box-configuration
  bootloader:
    owner: image-assembler
  cmdline:
    owner: target-definition
  firmware:
    source: pinned-package-or-artifact
  boot_state:
    owner: updater-or-boot-counter-service
```

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Two clean builds with identical declared inputs **MUST** produce the same selected kernel version and boot artefact metadata.

```yaml
verification:
  - class: VM
    runner: github-actions
    target: x86_64
```

The resulting x86_64 image boots independently of the build host’s installed kernel.

---

## Task 1.6 — Define the image assembly and boot bundle contract

The rootfs builder creates filesystem contents.

The image assembler alone owns:

- partition table;
- partition sizes;
- filesystem creation;
- filesystem labels;
- loop devices;
- mount points;
- final image compression.

The rootfs builder **MUST NOT** create a partition table.

The image assembler writes boot files according to the target boot bundle.

Target definitions supply boot parameters.

The rootfs builder does not own boot artefacts.

The updater may replace boot artefacts only if the release contract explicitly includes them.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions
```

The ownership boundary is represented in scripts and tests.

---

# LAYER 2 — Base System and Boot

For A95X, preserve CoreELEC's pinned init, udev, boot, identity, time, and service mechanisms unless the Layer 0.5 integration contract identifies a narrow required change. Apply this layer's behavioral and security outcomes through CoreELEC packages/overlays; do not reinstall a Debian base system or blindly mask CoreELEC services. Enumerate every service disabled because of Kodi removal and verify it has no retained non-Kodi hardware responsibility.

---

## Task 2.1 — Install systemd and base services

Install the minimal systemd environment required by AshipaOS.

Enable only services required by the image.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
```

---

## Task 2.2 — udev/device permissions

Create device rules for:

- graphics;
- input;
- serial devices where applicable;
- CEC;
- other explicitly required hardware.

Do not grant broad device access to `ashipaos`.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

The UI user can access required devices and cannot access unrelated privileged devices.

---

## Task 2.3 — Boot service skeleton

Create service units with explicit dependencies.

Avoid unnecessary dependencies on `systemd-udev-settle.service`.

Services **MUST** fail clearly when a required dependency is absent.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: VM
    runner: github-actions
```

---

## Task 2.4 — Disable conflicting services

Disable or mask only services that conflict with AshipaOS.

Record every masked service and why it is masked.

Do not blindly mask services because they exist in the base image.

### Verification

```yaml
verification:
  - class: VM
    runner: github-actions
```

Example:

```bash
systemctl list-units --state=masked
```

---

## Task 2.5 — Boot measurement

Measure:

```bash
systemd-analyze
systemd-analyze blame
systemd-analyze critical-chain
```

The performance target remains a target, not an unconditional architectural dependency.

Do not disable services or filesystem checks merely to hit a number without understanding the consequence.

### Verification

```yaml
verification:
  - class: VM
    runner: github-actions
```

Record the measured result.

---

## Task 2.6 — Identity and time

Define:

- machine-id generation;
- hostname policy;
- persistent identity across OS updates;
- time synchronization service;
- behaviour when RTC is absent or incorrect.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
```

The image does not depend on the build host’s identity or clock.

---

# LAYER 3 — Display Stack

---

## Task 3.1 — Install graphics stack

Install the target-appropriate Mesa/DRM stack.

Do not install unrelated driver packages merely because they exist in a generic package list.

Target definitions determine required graphics packages.

For A95X, retain the pinned CoreELEC graphics/display stack selected by Task 0.5.4. Do not install a generic Debian Mesa stack over it.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Record the renderer and DRM devices.

---

## Task 3.2 — Install Wayland/cage

Install the Wayland compositor and required runtime libraries for the Pi/x86_64 path. Cage/Wayland is not an A95X requirement unless Task 0.5.4 proves it necessary and compatible with the retained CoreELEC display and decode path.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A minimal fullscreen application launches under cage.

---

## Task 3.3 — Install mpv

Install mpv and the Python binding required by Jellyfin mpv shim.

Verify the actual installed package provides the required library/API.

Verification must occur inside the target rootfs or an equivalent target-equivalent environment, not merely on the build host.

For A95X, build and verify mpv/libmpv and Python-binding compatibility through the pinned CoreELEC package graph and the application bundle contract in Tasks 0.5.4–0.5.5. Debian package/import results are not proof for A95X.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Example:

```bash
python3 -c 'import mpv; print(mpv.MPV)'
```

The CI job must record whether this ran in:

- chroot;
- QEMU user emulation;
- VM;
- hardware.

---

## Task 3.4 — Create display service

The display service **MUST**:

- run as `ashipaos`;
- use the correct runtime directory;
- depend on required system services;
- restart on failure;
- log failures;
- not run as root.

Do not create arbitrary writable directories inside the immutable root filesystem at runtime.

This task now verifies the runtime user requirement that Layer 1 deliberately deferred.

For A95X, use the launcher selected in Task 0.5.4 and service defined in Task 0.5.6. Require unprivileged execution where supported and evidence for every device/group or unavoidable privilege granted.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A test application renders fullscreen.

The display process runs as `ashipaos`.

---

## Task 3.5 — Test mpv independently

Play a local test file through cage before adding Jellyfin mpv shim on Pi/x86_64. For A95X, run the independent local-media smoke test through the runtime selected in Task 0.5.4 before Jellyfin network playback; hardware-decode confirmation remains the separate Task 0.5.9 gate.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Record playback and hardware decode evidence.

---

# LAYER 4 — Network Stack

For A95X, do not reinstall or replace the confirmed CoreELEC network or firmware stack merely to standardize on Debian. Identify and retain the pinned CoreELEC network manager and persistent-state conventions from source. Wi-Fi hardware/driver operation is confirmed baseline; verify instead that no-Kodi integration, persistence, provisioning, and settings operations still work. Provisioning and settings writers must target the retained interfaces rather than assume ConnMan paths when pinned-source evidence differs. Credentials belong only in protected persistent storage and hardware-lab secrets, never in an image or evidence.

---

## Task 4.1 — Install ConnMan and WiFi dependencies

Install only the network packages required by the target.

The network state directory **MUST** live on persistent storage where the target architecture requires it.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Ethernet and/or WiFi reach `online`.

---

## Task 4.2 — Mount persistent storage

Mount the persistent partition at:

```text
/storage
```

Use a stable filesystem label or target-specific persistent identifier.

### Verification

```yaml
verification:
  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Example:

```bash
mountpoint /storage
```

---

## Task 4.3 — Test pre-provisioned WiFi

Use a test configuration in persistent storage.

Do not commit real WiFi credentials.

Use CI secrets or hardware-lab secrets for real test networks.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

The device connects without provisioning.

---

## Task 4.4 — Network-state detection

The network detector **MUST** distinguish:

- valid persistent configuration;
- Ethernet connectivity;
- WiFi requiring provisioning.

It **MUST NOT** interpret “no config file” as sufficient proof that provisioning is needed if another network path is already active.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Test:

- Ethernet;
- configured WiFi;
- unconfigured WiFi.

---

## Task 4.5 — Provisioning AP tools

Install and configure `hostapd` and `dnsmasq` for provisioning only.

They **MUST NOT** run as ordinary background services on a normally configured device.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Provisioning mode starts only when required.

---

## Task 4.6 — Provisioning portal

The portal **MUST**:

- validate input;
- avoid logging passwords;
- write configuration atomically;
- restrict access to the provisioning interface;
- terminate after successful configuration;
- reboot or restart networking only after configuration is durably written.

The provisioning contract should define:

- activation conditions;
- AP security policy;
- portal binding;
- timeout;
- retry behaviour;
- bad-credential behaviour;
- reboot-during-provisioning behaviour;
- credential ownership;
- relationship to `settingsd set_wifi`.

Recommended ownership rule:

> Provisioning owns first-run network bootstrap.  
> `settingsd` owns privileged runtime network changes.  
> Both must use the same validated network configuration writer.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A phone can connect, submit credentials, and the device subsequently joins the configured network.

---

# LAYER 5 — AshipaOS Application

---

## Task 5.1 — Install pinned Jellyfin mpv shim

The base image contains a pinned known-good application version.

Record:

- package;
- version;
- source;
- dependencies.

The base application is the fallback for app updates.

For A95X, Task 0.5.5 governs the CI-built bundle: the initial reproducible pin is upstream stable `v3.0.0`, with full commit, source hash, metadata-derived dependency lock, ABI contract, bundle hash, and signature. Do not invent a Python dependency list.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

---

## Task 5.2 — Create persistent application configuration

Application configuration belongs on `/storage`.

The immutable image **MUST** contain only defaults.

For A95X, configuration, Jellyfin credentials, identity, cache/downloads, and updater state remain outside both writable application slots and the immutable CoreELEC image.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

---

## Task 5.3 — Hardware decode configuration

Target-specific decoder configuration belongs in the target definition.

Example conceptual fields:

```yaml
graphics:
  renderer: ...

video:
  hwdec: ...
  codecs: ...
```

Do not hard-code Intel VAAPI configuration into a service shared by Amlogic/Pi targets. Do not hard-code an A95X `hwdec` value until Task 0.5.4 identifies the supported interface and Task 0.5.9 proves actual decoder selection.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Record actual decoder behaviour.

---

## Task 5.4 — First-run configuration

Create defaults only when persistent configuration does not already exist.

First-run operations **MUST** be idempotent.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Run first boot twice.

The second boot **MUST NOT** overwrite user configuration. On A95X, application activation, rollback, and CoreELEC rebase must also preserve existing configuration and identity.

---

## Task 5.5 — Launch Jellyfin mpv shim

The display service uses a per-target launcher. Pi/x86_64 launch through their declared cage path. A95X uses the CoreELEC runtime bridge recorded by Task 0.5.4 and service from Task 0.5.6, booting directly to the released Jellyfin MPV Shim full-screen built-in library/browser UI and player.

The launcher uses the target’s environment and persistent application path.

The service **MUST NOT** assume that the application update directory exists.

If the application payload is missing, the display service should show a recoverable error state rather than crash silently.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

The Jellyfin library browser appears and the client registers correctly with the Jellyfin server.

---

# LAYER 6 — Input and Remote Control

---

## Task 6.1 — Keyboard baseline

Confirm:

- arrows;
- Enter;
- Escape/back;
- pause.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

---

## Task 6.2 — CEC

Install and test CEC support only on targets that expose it.

Do not treat CEC availability as universal. On the exact A95X unit, CoreELEC baseline hardware, including Bluetooth, is confirmed, but Kodi mappings are not Jellyfin MPV Shim evidence. For each claimed CEC, Bluetooth remote, USB HID, or keyboard path, identify the retained CoreELEC event source and add only the minimal mapping/bridge required by the released Jellyfin UI.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Examples:

```bash
ls /dev/cec*
cec-client -l
```

---

## Task 6.3 — CEC key mapping

Map only verified input events.

Do not invent mpv commands for a frontend unless the frontend actually supports them.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Record real keycodes. Verify focus navigation, select, back, play/pause, and recovery from an unmapped key in the released UI. TV remote navigation must not be inferred from Kodi behavior.

---

## Task 6.4 — IR

On the exact A95X unit, preserve and document the confirmed CoreELEC input path, then verify Jellyfin navigation and playback controls. Kodi input behavior is not sufficient evidence.

For IR and every other claimed input, identify the retained event source and use only the minimal mapping/bridge required by the released Jellyfin UI. Use `ir-keytable` only when pinned-source and device evidence identify it as the actual path.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

Examples:

```bash
cat /proc/bus/input/devices
ir-keytable -t
```

Record the actual keycodes before creating the permanent keymap.

---

# LAYER 7 — Settings Bridge

For A95X, implement `settingsd` as a CoreELEC package/overlay against the actual retained service, network, and boot interfaces. `write_boot_config` must not alter the confirmed DTB, CoreELEC boot chain, or arbitrary files; expose only explicitly validated A95X operations. Application-slot activation is owned by the app updater and is not an unrestricted `settingsd` action. All protocol, authorization, and security requirements below remain unchanged.

---

## Task 7.1 — Define settingsd protocol

The previous one-shot `recv(4096)` protocol is replaced by a framed, bounded protocol.

Request:

```json
{
  "id": "request-id",
  "action": "reboot",
  "args": {}
}
```

Response:

```json
{
  "id": "request-id",
  "ok": true
}
```

Requirements:

- maximum request size;
- request framing;
- timeout;
- malformed JSON handling;
- unknown action rejection;
- action-specific validation;
- request ID echoed in response;
- no arbitrary shell execution;
- no arbitrary filesystem paths;
- secret redaction in logs;
- rate limiting;
- audit logging.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

The protocol and action schema are documented.

---

## Task 7.2 — Implement settingsd

Allowed actions remain narrow:

- reboot
- poweroff
- set_wifi
- toggle_ssh
- write_boot_config

Every action has explicit validation.

For `write_boot_config`, use a whitelist of allowed keys and validate values as well as names.

Configuration writes **MUST** be atomic.

### Authorization contract

Define which callers may perform which actions.

Example:

```yaml
settingsd:
  transport: unix-socket
  socket: /run/ashipaos/settings.sock
  authentication:
    - unix-peer-credentials
  authorization:
    reboot: ashipaos-ui
    poweroff: ashipaos-ui
    set_wifi: ashipaos-ui
    toggle_ssh: ashipaos-ui
    write_boot_config: ashipaos-ui-with-validation
  limits:
    max_request_bytes: 65536
    timeout_ms: 5000
    rate_limit: true
  logging:
    audit: true
    redact_secrets: true
```

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A normal AshipaOS process can perform an allowed action but cannot execute an arbitrary privileged command.

Negative tests must cover:

- oversized request;
- malformed JSON;
- unknown action;
- invalid arguments;
- unauthorized caller;
- rapid repeated requests;
- secret values in logs.

---

## Task 7.3 — settingsd service

Run settingsd as root with:

- automatic restart;
- explicit dependencies;
- restricted socket permissions;
- a private runtime directory.

The socket **MUST** be:

```text
/run/ashipaos/settings.sock
```

and accessible only to the intended group.

Where practical, apply systemd hardening to reduce privilege surface.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

---

# LAYER 8 — OS OTA

The Pi/x86_64 OTA design remains intact. A95X OS updates are a distinct profile: signed AshipaOS releases built from a deliberately pinned `ashipaek0/CoreELEC` state, never direct installation of arbitrary upstream CoreELEC images. Before claiming A95X rollback, inspect and document the pinned CoreELEC update and boot mechanism; do not assume the Debian `.old` SquashFS method or boot-counter location applies.

OS checking, application, reboot, health, and recovery remain separate from no-reboot application-bundle updates. A Jellyfin application release must not force an OS rebuild unless its declared CoreELEC/native ABI constraints cannot be met by the current base.

The OTA concept is retained, but its contracts are tightened.

---

## 8.1 Release manifest

A manifest **MUST** contain at least:

```json
{
  "channel": "stable",
  "version": "1.0.0",
  "target": "x86_64",
  "date": "YYYY-MM-DD",
  "url": "...",
  "sha256": "...",
  "size_bytes": 0,
  "min_version": "0.9.0",
  "max_version": null,
  "boot_artefacts_updated": false,
  "rollback_scope": ["rootfs"],
  "release_notes": "...",
  "signature": null
}
```

A future signed-manifest mechanism should be adopted before treating SHA-256 alone as an authenticity mechanism.

For the current implementation, explicitly distinguish:

- SHA-256 = integrity
- signature = authenticity

Do not claim that a hash alone authenticates the publisher.

For A95X, signatures are mandatory. Bind the OS manifest to `a95x-f3-air`, CoreELEC tag/full commit, fork commit, image hash, DTB filename/hash, minimum storage and schema compatibility, and the evidence-backed CoreELEC rollback/recovery contract.

Minimum OTA trust contract:

- HTTPS-only manifest retrieval;
- pinned or known manifest URL;
- manifest validation before payload download;
- payload size and SHA-256 validation;
- target binding;
- channel binding;
- version comparison rules;
- downgrade policy;
- failed-release blacklist.

---

## Task 8.2 — Update checker

The checker has a strict exit contract:

```text
0 = no update
1 = check failed
2 = update available
```

This is intentional.

Critical implementation rule:

Any caller using:

```bash
set -e
```

**MUST** invoke the checker in a conditional context:

```bash
if /usr/lib/ashipaos/check-update.sh; then
    ...
else
    status=$?
    ...
fi
```

or:

```bash
set +e
/usr/lib/ashipaos/check-update.sh
status=$?
set -e
```

Do not capture a command substitution whose command can legitimately return 2 under `set -e`.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions
```

Tests **MUST** explicitly exercise all three exit statuses.

---

## Task 8.3 — OS update applier

The updater **MUST** implement:

```text
download
→ validate manifest
→ download candidate
→ verify size
→ verify SHA-256
→ stage
→ activate
→ sync
→ reboot
```

The update **MUST NOT** destroy the only known-good copy before the new artefact is safely staged.

The updater **MUST** have cleanup traps for:

- temporary download files;
- mount points;
- loop devices;
- temporary directories.

The updater should also handle:

- single-instance locking;
- insufficient disk space;
- corrupted downloads;
- interrupted updates;
- target mismatch;
- blacklisted failed releases.

The current `.old` model is retained for the Pi/x86_64 architecture. It does not apply to A95X unless the pinned CoreELEC mechanism is inspected and proves an equivalent contract.

### Rollback contract

The current design provides a previous SquashFS fallback.

It does not automatically constitute complete rollback of every boot artefact unless the kernel, initramfs, DTB and boot configuration are also versioned and restored together.

Therefore the release contract **MUST** explicitly state what is rolled back.

For the current single-slot model:

```text
Rollback guarantee: previous root filesystem payload.
```

Do not claim full boot-artefact A/B rollback.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A known-good previous image can be restored after a simulated failed update.

---

## Task 8.4 — OS update timer

The timer **MUST** distinguish checking from applying.

If the intended policy is:

```text
check daily
```

then the service runs the checker.

If the intended policy is:

```text
automatically apply approved updates
```

then the service **MUST** invoke an orchestrator that:

- checks;
- interprets exit code 2;
- verifies policy;
- applies;
- records outcome.

The timer **MUST NOT** claim automatic updates while only invoking `check-update.sh`.

The orchestrator should include:

- lock file;
- randomized delay/jitter;
- retry policy;
- network-online dependency;
- update state persistence;
- failure reporting.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

A test update follows the declared policy end-to-end.

---

# LAYER 8.5 — Jellyfin MPV Shim Application Updates

The application update mechanism remains independent of OS updates. Pi/x86_64 retain the behavior specified below. For A95X, the signed A/B profile in each task is mandatory and supersedes `PYTHONPATH` shadowing, mutable `pip --target` installs, and copying a live `site-packages` tree as rollback. Production A95X devices consume only promoted AshipaOS bundles and never run `pip`, compile, resolve mutable dependencies, or trust PyPI directly.

For A95X, Tasks 8.5.1–8.5.7 require `STATIC` and `BUILD` verification on `github-actions` for slot, feed, trust, manifest, staging, validation, activation, timer, and failure-state contracts. Task 8.5.8 additionally requires portable `VM` tests on `github-actions`, exact-box `HARDWARE` tests on `hardware-lab`, and visible continuity/recovery `MANUAL` tests on `human`. An unavailable required runner yields `BLOCKED`; no lower verification class substitutes for it.

---

## Task 8.5.1 — Persistent application slots

Use:

```text
/storage/.local/lib/ashipaos-app/
├── current/
├── previous/
├── pending/
└── state.json
```

Prefer complete staged application bundles over mutating the live installation.

The existing `PYTHONPATH` shadowing mechanism may be retained during Pi/x86_64 migration, but the final contract should use an atomic application activation point.

**A95X profile:** use `/storage/.local/lib/ashipaos-app/slots/A` and `slots/B`, an atomically updated active-slot selector, and durable updater state stored outside both slots. Keep configuration, Jellyfin credentials, identity, cache, downloads, and logs outside both slots. Retain the immutable OS-bundled known-good application as rescue fallback when neither writable slot validates.

---

## Task 8.5.2 — Check upstream version

The checker **MUST** report:

```text
0 = current
1 = failure
2 = update available
```

and the orchestrator **MUST** handle exit 2 explicitly.

Do not let `set -e` terminate the update path.

**A95X profile:** the device queries a signed AshipaOS stable app feed, not PyPI or a mutable GitHub branch. CI may discover upstream tags, but rejects drafts/prereleases, resolves the tag to a full commit, hashes source, builds/tests the complete bundle, and publishes only after explicit AshipaOS promotion. The device rejects quarantined releases until a newer eligible version exists.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

Tests cover:

- current version;
- newer version;
- network failure;
- malformed upstream response;
- previously failed version.

---

## Task 8.5.3 — Stage update

The updater downloads into:

```text
pending/
```

It **MUST NOT** overwrite `current/`.

Verify package metadata and imports before activation.

**A95X profile:** download to a temporary path on persistent storage. Before safe extraction into the inactive slot, verify signed manifest/key ID, stable channel, monotonically acceptable version and downgrade policy, exact target, CoreELEC base, architecture, Python/native ABI constraints, declared size, and SHA-256. Use a single-instance lock, sufficient-space check, durable state, safe path/symlink handling, fsync/atomic rename where required, and interruption-safe cleanup. Never alter the active slot or rescue application.

---

## Task 8.5.4 — Validate staged application

At minimum:

- package import;
- version check;
- dependency import;
- configuration load.

If validation fails, delete the pending version and leave the current version untouched.

**A95X profile:** without installer hooks or device-side compilation, validate archive paths/symlinks, permissions, manifest completeness, dependency closure, imports, reported version, configuration loading against a non-secret fixture, entrypoint startup, and every CoreELEC/Python/native ABI constraint. Failure leaves the active selector untouched and quarantines or removes the candidate according to policy.

---

## Task 8.5.5 — Activate and health-check

Activation should be atomic where the filesystem permits:

```text
current → previous
pending → current
```

Then restart the display service.

Health check:

- service becomes active;
- service remains active for observation period;
- restart count remains within the declared threshold;
- application reports expected version.

If health check fails:

```text
current → failed
previous → current
```

and record the failed version so the timer does not repeatedly install it.

**A95X profile:** atomically select the inactive slot, restart only the application service, and require both process stability and a bounded application-level readiness signal before commit. On failure, atomically restore the former selector, restart and verify the former app, quarantine the candidate, and preserve evidence. Never destroy the only known-good slot. If neither writable slot validates, select the immutable rescue app and report degraded state.

---

## Task 8.5.6 — Timer

The application update timer is independent of the OS timer.

It **MUST** invoke the application update orchestrator, not merely the checker.

The service runs as root only because it needs to activate the application and restart the display service.

Its command surface must remain narrow.

**A95X profile:** run daily with jitter, network-online ordering, a single-instance lock, bounded retry/backoff, and automatic apply policy. The orchestrator performs check, download, verification, inactive-slot staging, activation, health check, and outcome recording. A checker-only timer is not automatic updating. It never reboots or invokes the OS updater.

---

## Task 8.5.7 — Application manifest

The application manifest should include compatibility constraints.

Example:

```json
{
  "name": "jellyfin-mpv-shim",
  "version": "1.2.3",
  "channel": "stable",
  "url": "...",
  "sha256": "...",
  "size_bytes": 0,
  "os_min_version": "1.0.0",
  "os_max_version": null,
  "targets": ["pi4", "pi5", "x86_64", "amlogic"],
  "capabilities": ["display", "network"],
  "entrypoint": "..."
}
```

The app updater must reject incompatible app releases.

**A95X profile:** the signed manifest additionally requires upstream version/tag/full commit, AshipaOS bundle revision, target `a95x-f3-air`, CoreELEC base constraints, architecture/Python/native ABI, signature/key ID, dependency-lock hash, bundle format, and rollback/health policy. Missing, unauthenticated, wrong-channel, downgraded, or incompatible bundles are rejected. Pi/x86_64 manifests retain their own target fields and must not claim A95X compatibility without these fields.

---

## Task 8.5.8 — End-to-end application update test

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Verify:

- newer version is detected;
- update is staged;
- application restarts without reboot;
- new version persists across reboot;
- deliberately broken release rolls back;
- failed release is not retried indefinitely;
- newer release can subsequently be installed.

For A95X also test first install; A-to-B and B-to-A updates; invalid signature/key; wrong hash, size, channel, target, CoreELEC/Python/native ABI; downgrade; missing dependency; unsafe traversal/symlink archive; insufficient space; interruption or power loss during download, extraction, activation, commit, and rollback boundaries; corrupt selector/state; crash loop; readiness failure; failed rollback; quarantine/no retry loop and bypass attempt; both writable slots invalid; rescue fallback; and unchanged user configuration/identity.

A95X verification requires `STATIC` and `BUILD` on `github-actions` for feed/manifest/trust and portable updater tests, `VM` on `github-actions` only for portable state-machine behavior, `HARDWARE` on `hardware-lab` for real activation/reboot/rollback/rescue, and `MANUAL` on `human` for UI continuity. Unavailable required runners yield `BLOCKED`; VM evidence cannot pass A95X boot, display, input, or decode gates.

---

# LAYER 9 — Image Flasher and First Boot

---

## Task 9.0 — Raspberry Pi Imager repository

Retain the existing plan to use Raspberry Pi Imager’s repository mechanism for supported Pi/x86_64 targets rather than building a custom flashing application prematurely.

The repository metadata **MUST** distinguish targets and versions.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions
```

---

## Task 9.1 — Amlogic installation documentation

Create `docs/amlogic-install.md` for only the supported exact A95X F3 Air unit and the AshipaOS image derived from `CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic` at the pinned 21.3-Omega/fork inputs. The release manifest must provide the exact produced AshipaOS image filename; documentation must not use an unversioned generic filename.

The verified installation procedure is:

1. verify the signed image manifest, image hash, target, and CoreELEC/fork pins;
2. write the image to removable media;
3. copy `sm1_s905x3_4g_1gbit.dtb` to the FAT boot-partition root as `dtb.img` and verify its identity/hash;
4. boot using the same confirmed process used by the working CoreELEC baseline;
5. if the candidate fails, return to the last known-good 21.3-Omega-based AshipaOS image on removable media.

Do not present alternative DTBs, Debian partition layouts, bootloader replacement, eMMC installation, UART availability, serial diagnostics, or recovery-button behavior as confirmed without separate evidence. Do not generalize these instructions to another A95X revision or S905X3 box.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
    target: a95x-f3-air
    proves: exact image/DTB verification, scoped install steps, and known-good recovery
```

---

## Task 9.2 — First-boot acceptance test

On fresh hardware:

```text
[ ] boot;
[ ] UI appears;
[ ] Ethernet works;
[ ] pre-provisioned WiFi works;
[ ] unprovisioned WiFi enters provisioning;
[ ] provisioning succeeds;
[ ] keyboard navigation works;
[ ] target-specific remote works;
[ ] media playback works;
[ ] hardware decode works;
[ ] pause works;
[ ] back works;
[ ] Jellyfin sees the correct client.
```

A95X acceptance additionally requires, with baseline facts and integration results recorded separately:

```text
[ ] exact image and sm1_s905x3_4g_1gbit.dtb-as-dtb.img identity verified;
[ ] Kodi absent;
[ ] released full-screen Jellyfin library/browser UI appears automatically;
[ ] server registration/login succeeds without credentials in evidence;
[ ] configuration and identity survive reboot;
[ ] claimed keyboard/CEC/IR/Bluetooth/USB input navigation and playback controls work;
[ ] display, audio, Ethernet, Wi-Fi, Bluetooth where exercised, storage, and other relied-upon hardware remain operational after replacement;
[ ] representative media playback succeeds through Jellyfin MPV Shim;
[ ] each advertised codec, including 10-bit HEVC where claimed, has actual decoder evidence.
```

Do not rediscover the DTB or Wi-Fi driver as first-boot work. Visible UI/navigation requires `MANUAL` evidence; device, network, and decoder behavior requires `HARDWARE` evidence on the exact box.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Where physical observation is required:

```yaml
verification:
  - class: MANUAL
    runner: human
```

---

# LAYER 10 — Hardening, Rollback and Release

---

## Task 10.1 — Firewall

Use nftables with an explicit policy.

The firewall **MUST** reflect actual AshipaOS network requirements.

Do not blindly block discovery or required local traffic.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions

  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

From another LAN machine:

- expected ports are reachable;
- unexpected ports are not;
- SSH is inaccessible when disabled.

---

## Task 10.2 — Release metadata

Do not write release metadata using an unrecorded host date.

Generate:

```text
/etc/ashipaos/version
/etc/ashipaos/target
/etc/ashipaos/build-id
```

The build ID should derive from declared source/build inputs.

A human-readable build date may be recorded separately if reproducibility policy permits it.

Release metadata should also include:

- source manifest;
- package lock;
- kernel/boot artefact metadata;
- CI job ID;
- container image digest, if used;
- SBOM reference, if generated.

For A95X also record the CoreELEC repository/tag/full commit, fork commit, DTB filename/hash, no-Kodi dependency-closure and image-scan result, selected runtime bridge, initial/rescue app tag and commit, dependency-lock hash, bundle hash/signature/key ID, and final image hash.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

---

## Task 10.3 — Boot-counter rollback

Retain the existing boot-counter rollback as the current single-slot recovery mechanism.

The implementation **MUST**:

- increment the candidate boot counter;
- boot the candidate;
- reset the counter only after successful system readiness;
- restore the previous SquashFS after the declared failure threshold.

Do not call this a complete A/B boot system. This generic `.old` SquashFS rollback applies to Pi/x86_64 only unless the pinned CoreELEC boot/update mechanism proves it for A95X. A95X OS rollback/recovery remains separate from the mandatory application-slot rollback.

Each target must define:

```yaml
boot_state:
  counter_location: <target-specific>
  success_signal: <target-specific>
  failure_threshold: <value>
  rollback_scope:
    rootfs: true
    kernel: false
    dtb: false
    bootloader_config: false
  recovery_method: <target-specific>
```

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

Simulate repeated failed boots and confirm restoration of the previous root filesystem.

---

## Task 10.4 — SSH diagnostics

SSH is disabled by default.

When enabled:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Only the intended user may log in.

Enabling SSH through settingsd **MUST** be the only supported UI path.

Define lifecycle rules:

- whether SSH auto-disables;
- whether keys are added temporarily;
- where authorized keys are stored;
- whether enabling SSH survives reboot;
- whether it is disabled by OS update;
- whether it is audited.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

SSH works with a configured key when enabled and is inaccessible when disabled.

---

## Task 10.5 — Final release build

The final build pipeline is conceptually:

```text
clean
→ verify source state
→ build rootfs
→ install pinned packages
→ apply target configuration
→ run static tests
→ assemble image
→ validate image structure
→ boot VM where applicable
→ run hardware acceptance suite
→ generate release metadata
→ generate checksum
→ publish release candidate
```

For A95X, use a separate pipeline:

```text
fetch and verify immutable CoreELEC/fork pin
→ review/apply the AshipaOS package/overlay delta
→ exclude Kodi and verify dependency closure
→ build the selected runtime and signed v3.0.0 rescue bundle
→ build the CoreELEC-derived image
→ inspect DTB, package manifest, bundle, metadata, and Kodi absence
→ sign/hash the image and manifests
→ run exact-box A95X hardware acceptance
```

Do not run `debootstrap` or the Debian image assembler for A95X. The generic rootfs pipeline above remains unchanged for Pi/x86_64.

The image assembler **MUST** clean up loop devices and mounts even on failure.

Example cleanup contract:

```bash
cleanup() {
    set +e
    # unmount any mounted filesystems
    # detach any loop device
    # remove temporary directories
}

trap cleanup EXIT INT TERM
```

Never leave a loop device attached because a build command failed.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: VM
    runner: github-actions
    where_supported: true

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

---

## Task 10.6 — Upgrade path validation

A release candidate must not be validated only as a clean install.

Test:

- upgrade from previous release;
- upgrade from N-1 release where practical;
- application update from previous app version;
- configuration migration;
- storage compatibility;
- rollback from failed upgrade;
- preservation of user configuration;
- preservation of WiFi configuration;
- preservation of AshipaOS client identity.

For A95X, independently test a CoreELEC/OS rebase upgrade, application A-to-B/B-to-A upgrade, application rollback/rescue, persistent configuration and identity, and recovery to the prior supported OS pin. App and OS mechanisms must not share activation or rollback state.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: target-specific
```

---

# 11. Automated verification suite

The repository **MUST** contain tests corresponding to the major contracts.

---

## 11.1 CI stages

Recommended CI stages:

```text
PR
 ↓
static tests
 ↓
build image
 ↓
inspect image
 ↓
boot image in VM
 ↓
PASS / FAIL
```

For hardware:

```text
release candidate
 ↓
deploy candidate
 ↓
hardware runner
 ↓
boot
 ↓
test
 ↓
serial/log evidence
 ↓
PASS / FAIL
```

A coding agent cannot substitute assertion for CI evidence.

---

## 11.2 Static tests

Examples:

- `test-shell-scripts.sh`
- `test-no-box-hardcoding.sh`
- `test-target-schema.sh`
- `test-systemd-units.sh`
- `test-update-exit-contract.sh`
- `test-settingsd-schema.sh`
- `test-no-default-password.sh`
- `test-workflow-files.sh`
- `test-evidence-schema.sh`

### No box hard-coding test

The generic Amlogic package tree **MUST** fail the test if it contains A95X-specific references.

A95X static tests also validate immutable CoreELEC and app pins, the confirmed DTB, absence of forbidden transitional branch/project language in normative A95X instructions, no box hard-coding in generic application code, application-manifest schema, and mandatory signature metadata.

---

## 11.3 Build tests

Verify:

- rootfs construction;
- package installation;
- image creation;
- partition labels;
- filesystem types;
- expected files;
- kernel artefact selection;
- release metadata;
- checksum generation.

For A95X, BUILD tests additionally verify the pinned CoreELEC source build, Kodi exclusion and dependency closure, final image contents and DTB, application bundle dependency closure/native ABI, safe archive handling, SBOM/lock, checksums, signatures, and reproducibility metadata.

---

## 11.4 VM tests

Where supported:

- boot;
- systemd;
- users;
- services;
- settingsd;
- firewall;
- updater;
- rollback logic.

Hardware-specific display/decode/input tests **MUST NOT** be falsely marked as passed by VM tests. VM tests may exercise portable A95X updater state machines and malformed inputs, but cannot pass A95X boot, display, input, network, or decode gates.

---

## 11.5 Hardware tests

Hardware tests are target-specific.

Each target has an acceptance matrix:

| Target | Boot | Display | Network | Input | CEC | IR | Hardware decode | Provisioning | OTA | Rollback |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Pi 4 |  |  |  |  |  |  |  |  |  |  |
| Pi 5 |  |  |  |  |  |  |  |  |  |  |
| x86_64 |  |  |  |  |  |  |  |  |  |  |
| A95X F3 Air |  |  |  |  |  |  |  |  |  |  |

For the exact A95X F3 Air, `sm1_s905x3_4g_1gbit.dtb` and baseline Wi-Fi are confirmed inputs; serial console is optional diagnostic infrastructure, not a prerequisite or confirmed fact. Required A95X `HARDWARE`/`MANUAL` evidence covers no-Kodi boot-to-UI, retained hardware/network behavior, navigation, playback and decoder selection, signed application activation/rollback/rescue, and future OS rebase acceptance. Stock CoreELEC baseline results cannot pass these post-replacement gates.

---

## 11.6 Negative tests

The test suite must include failure paths.

Examples:

### OTA negative tests

- malformed manifest;
- wrong target manifest;
- corrupted download;
- incorrect SHA-256;
- insufficient disk space;
- reboot during download;
- reboot during activation;
- failed health check;
- blacklisted failed release;
- downgrade attempt.

### Application update negative tests

- broken bundle or missing dependency;
- invalid signature, unknown/revoked key, wrong hash, or wrong size;
- wrong channel, target, CoreELEC/Python/native ABI, or downgrade;
- unsafe archive traversal or symlink;
- failed import, configuration load, entrypoint, or readiness signal;
- crash-looping app;
- insufficient space;
- power loss at every download, extraction, activation, commit, and rollback state boundary;
- partially written inactive slot;
- corrupt selector or state;
- both writable slots invalid;
- failed rollback or rescue selection;
- quarantine bypass or repeated retry;
- unchanged user configuration and identity after every failure.

### settingsd negative tests

- oversized request;
- malformed JSON;
- unknown action;
- invalid arguments;
- unauthorized caller;
- rapid repeated requests;
- secret values in logs.

### Provisioning negative tests

- wrong WiFi password;
- hidden SSID;
- DHCP failure;
- portal interruption;
- reboot during provisioning.

### Boot rollback negative tests

- kernel panic simulation;
- service crash-loop;
- storage missing;
- corrupted config;
- boot counter not reset.

---

# 12. Update state machines

---

## 12.1 OS update

```text
IDLE
   ↓
 CHECK
   ├── no update → IDLE
   ├── failure → ERROR
   └── update → DOWNLOAD
                     ↓
                  VERIFY
                     ↓
                   STAGE
                     ↓
                  ACTIVATE
                     ↓
                   REBOOT
                     ↓
               HEALTH / BOOT
               ├── success → COMMIT
               └── failure → ROLLBACK
```

No transition may destroy the only recoverable image.

---

## 12.2 Application update

For Pi/x86_64, retain the generic application activation flow:

```text
IDLE
  ↓
 CHECK
  ├── current → IDLE
  ├── failure → ERROR
  └── update → DOWNLOAD
                   ↓
                 STAGE
                   ↓
                VALIDATE
                   ↓
                ACTIVATE
                   ↓
               HEALTH-CHECK
               ├── success → COMMIT
               └── failure → RESTORE
```

For the A95X signed A/B profile:

```text
IDLE
  ↓
CHECK
  ├── current → IDLE
  ├── failure → ERROR
  └── update → DOWNLOAD
                   ↓
          VERIFY SIGNED MANIFEST
                   ↓
            VERIFY PAYLOAD
                   ↓
        STAGE INACTIVE SLOT
                   ↓
         OFFLINE VALIDATE
                   ↓
          ATOMIC ACTIVATE
                   ↓
              RESTART
                   ↓
            HEALTH CHECK
          ├── success → COMMIT
          └── failure → RESTORE PRIOR SELECTOR/SERVICE
                              ↓
                    MARK CANDIDATE FAILED
                              ↓
                  FORMER HEALTHY SLOT
```

Failure before activation leaves the active slot untouched. Failure after activation restores and verifies the prior selector/service and quarantines the candidate. If neither writable slot validates, select the immutable OS-bundled rescue application and report degraded state. No transition may modify persistent user configuration, credentials, identity, cache/downloads, or updater state ownership, or destroy the only known-good application.

Pi/x86_64 retain their target-specific application activation contract, subject to the same no-live-mutation and recovery invariants.

---

## 12.3 Provisioning

```text
FIRST_BOOT
   ↓
CHECK_NETWORK
 ├── online → NORMAL
 └── offline/unconfigured
          ↓
     PROVISIONING
          ↓
      CREDENTIALS
          ↓
      CONNECTING
       ├── success → NORMAL
       └── failure → PROVISIONING
```

The provisioning contract must also define edge cases:

- Ethernet online but WiFi unconfigured;
- saved WiFi credential failure;
- DHCP failure;
- bad credentials;
- reboot during provisioning;
- concurrent `settingsd set_wifi` request.

---

# 13. Release invariants

A release **MUST NOT** be published unless:

- the build inputs are recorded;
- target is explicit;
- package versions are pinned;
- kernel artefacts are explicitly selected;
- no host kernel is copied into the image;
- CI build environment is pinned or recorded;
- image structure passes validation;
- static tests pass;
- relevant VM tests pass;
- hardware acceptance tests pass where hardware is available;
- OS update path passes;
- OS rollback path passes according to documented guarantee;
- application update path passes;
- application rollback passes;
- provisioning passes;
- firewall passes;
- no default administrative password exists;
- privileged IPC is restricted;
- target-specific assumptions are documented;
- Amlogic hardware facts have appropriate status labels and evidence;
- release checksum is generated;
- release manifest is generated;
- evidence archive is retained;
- upgrade from previous release has been tested where practical.

For A95X specifically, release invariants require the exact CoreELEC and Jellyfin pins, confirmed DTB, no-Kodi package/image proof, selected runtime bridge, signed target/ABI-compatible application bundle, app rollback/rescue proof, and complete post-replacement hardware integration evidence. A stable upstream app tag is not automatically an AshipaOS release; its CI-built bundle must pass promotion gates. A CoreELEC rebase candidate cannot replace the supported pin until baseline reconfirmation and all no-Kodi, integration, update, recovery, and decode gates pass.

If hardware evidence is unavailable for a required target, the release is `BLOCKED` and is not a release candidate for that target.

---

# 14. Quick reference build order

| Layer | Scope | Done when |
|---|---|---|
| 0 | Canonical builder environment | Toolchain, repository, and CI are controlled |
| 0.5 | Amlogic/CoreELEC | Pinned `ashipaek0/CoreELEC` excludes Kodi, boots the exact box via the confirmed DTB into the released Jellyfin UI, preserves required hardware behavior, and proves Jellyfin playback/decoder integration |
| 1 | Debian rootfs | Minimal rootfs builds for explicit Pi/x86_64 target; skipped by A95X |
| 2 | Base system | systemd, users, devices and services work |
| 3 | Display | Wayland/cage/mpv render correctly |
| 4 | Network | Ethernet/WiFi/provisioning work |
| 5 | Application | Jellyfin library browser works |
| 6 | Input | Keyboard/CEC/IR work where supported |
| 7 | Settings | Privileged settings operations are safely exposed |
| 8 | OS OTA | Update, activation and declared rollback work |
| 8.5 | App OTA | App update, health check and rollback work independently |
| 9 | Distribution | Images can be installed and first boot passes |
| 10 | Hardening/release | Security, rollback, reproducibility and acceptance gates pass |

For A95X, Layers 2–10 supply shared behavioral contracts but use the CoreELEC-specific implementation, package/overlay, boot, update, and verification paths defined by Layer 0.5.

---

# 15. Refactoring decisions recorded by this guide

---

## Kept

- Layer 0–10 roadmap.
- Separate Amlogic/CoreELEC pipeline, with CoreELEC as the permanent A95X OS/hardware base rather than a temporary extraction source.
- The user's exact A95X F3 Air as the first and only current Amlogic box scope.
- Confirmed 21.3-Omega source/DTB/hardware baseline, without reopening it as provisional.
- Kodi exclusion at package-graph time with no fallback.
- Released upstream Jellyfin MPV Shim built-in UI at initial pin v3.0.0.
- Pinned-source runtime-bridge discovery instead of assumed cage/Wayland or guessed hardware decode.
- Signed CI-built A/B app bundles with immutable rescue fallback.
- Generic Jellyfin package versus box-specific configuration.
- Separate OS and application update mechanisms.
- Current `.old` SquashFS rollback model for this release generation.
- Raspberry Pi Imager as the preferred Pi/x86_64 flashing path.
- Incremental task-level verification.
- Verification classes.
- Exit-code protocols for update checkers.
- State machines for OS update, app update, and provisioning.

---

## Added

- GitHub repository as source of truth.
- GitHub Actions as canonical build environment.
- Explicit distinction between remote CI verification and physical hardware verification.
- Verification runner concept.
- Remote hardware lab architecture.
- Evidence contract for all verification.
- Evidence-backed hardware facts.
- Boot bundle ownership contract.
- Stronger storage contract.
- Stronger settingsd authorization and schema expectations.
- OTA trust-model boundaries.
- Application manifest compatibility rules.
- Negative test requirements.
- Upgrade-path validation.
- CI workflow skeleton as a Layer 0 task.
- Blocked state for unavailable hardware verification.

---

## Changed

### Project name

The project is now named **AshipaOS**.

All references to the previous project name are replaced.

Examples:

- user: `ashipaos`
- settings socket: `/run/ashipaos/settings.sock`
- version metadata: `/etc/ashipaos/version`
- update checker: `/usr/lib/ashipaos/check-update.sh`
- application slots: `/storage/.local/lib/ashipaos-app/`

---

### Confirmed implementation defects corrected

#### OS update timer

A checker-only timer is no longer described as automatic application.

The declared policy must match the command actually invoked.

#### App update `set -e`

Exit code `2` is a valid control-flow result.

Callers **MUST** capture it safely.

#### x86_64 kernel

Host kernel copying is prohibited.

Kernel source/package/version becomes an explicit build input.

#### Layer dependency fix

The AshipaOS user task no longer requires a running display process.

Display-process user verification is performed in the display service task.

---

## Deliberately deferred

### Full A/B OS slots

The current release generation retains the previous SquashFS rollback model.

A full A/B architecture remains a future upgrade because it requires coordinated versioning of:

- kernel
- initramfs
- DTB
- boot configuration
- root filesystem
- boot state

It **MUST NOT** be silently introduced under the existing `.old` contract.

### Signed OTA

The generic manifest schema supports signatures. A95X OS and application release manifests require signatures before promotion; integrity-only payloads are not eligible for automatic A95X release/update.

---

# 16. Agent operating rules

A coding agent implementing this guide **MUST** follow these rules:

1. Read the repository before editing.
2. Do not invent missing hardware facts.
3. Do not replace `UNKNOWN` with an assumption.
4. Do not modify another layer merely to make the current task appear to pass.
5. Preserve target isolation.
6. Run the verification required by the current task.
7. Respect the required runner.
8. If verification is impossible because the runner is unavailable, mark it blocked rather than claiming success.
9. Record discovered hardware facts in the appropriate configuration with evidence.
10. Do not introduce an unpinned dependency into a release build.
11. Do not copy host kernel/firmware artefacts into a target image unless the artefact is itself an explicit, reproducible build input.
12. Treat exit codes that are part of a documented protocol as data, not generic failures.
13. Never leave temporary mounts or loop devices behind.
14. Never overwrite the only known-good update payload before the candidate is safely staged.
15. Never expose arbitrary privileged execution through settingsd.
16. Never claim hardware support based solely on chipset family or similarity to another device.
17. Never claim a CI-passed task has also passed hardware verification unless hardware evidence exists.
18. Never use a local developer workstation as the authoritative release builder.
19. Never commit secrets.
20. When the guide and the repository disagree, stop and reconcile the source of truth before implementing the affected task.
21. Do not reopen the confirmed A95X 21.3-Omega, DTB, or baseline hardware facts without new contradictory evidence.
22. Do not use stock CoreELEC success to pass AshipaOS/Jellyfin integration.
23. Do not apply Debian, cage, Wayland, VAAPI, V4L2-M2M, or guessed `hwdec` instructions to A95X without pinned-source and exact-target evidence.
24. Do not install Kodi and delete it afterward, or retain it as fallback/recovery.
25. Do not let production devices build, run `pip`, or resolve application dependencies.
26. Do not modify Pi/x86_64 paths while implementing an A95X-only task.

---

# 17. Definition of Done

AshipaOS is ready for a release candidate only when the complete target-specific acceptance matrix passes.

For each supported target:

```text
CI
   ✓ GitHub Actions static tests pass
   ✓ GitHub Actions build tests pass
   ✓ relevant VM tests pass
   ✓ image structure validates
   ✓ checksums generated
   ✓ release manifest generated

BUILD
   ✓ clean build
   ✓ pinned dependencies
   ✓ correct kernel/boot artefacts
   ✓ valid image structure

BOOT
   ✓ boots
   ✓ services start
   ✓ persistent storage mounts

DISPLAY
   ✓ compositor
   ✓ mpv
   ✓ Jellyfin client

NETWORK
   ✓ Ethernet
   ✓ WiFi where supported
   ✓ provisioning

INPUT
   ✓ keyboard
   ✓ CEC where supported
   ✓ IR where supported

MEDIA
   ✓ playback
   ✓ target hardware decode

SETTINGS
   ✓ privileged actions restricted and functional

UPDATES
   ✓ OS update
   ✓ OS rollback according to documented guarantee
   ✓ app update
   ✓ app rollback
   ✓ upgrade from previous release where practical

SECURITY
   ✓ firewall
   ✓ no default administrative password
   ✓ restricted privileged IPC
   ✓ SSH disabled by default

RELEASE
   ✓ version metadata
   ✓ target metadata
   ✓ checksums
   ✓ release manifest
   ✓ acceptance evidence
   ✓ hardware evidence where hardware runner exists
```

For `a95x-f3-air`, completion additionally requires:

```text
BUILD
   ✓ canonical CoreELEC fork and app source pinned
   ✓ reproducible metadata-derived dependency lock/SBOM
   ✓ Kodi absent from package graph and image
   ✓ confirmed DTB installed and verified as dtb.img
   ✓ image and app bundle signed and hash-recorded

BOOT / UI
   ✓ exact box boots directly into released full-screen Jellyfin browser/player
   ✓ no Kodi or desktop fallback

HARDWARE INTEGRATION
   ✓ retained display, audio, Ethernet/Wi-Fi, Bluetooth and input paths used by the product, storage, and other relied-upon CoreELEC hardware work after replacement

MEDIA
   ✓ Jellyfin playback works
   ✓ each claimed codec has captured decoder evidence

APP UPDATE
   ✓ promoted stable feed and signed A/B activation
   ✓ reboot persistence, rollback, quarantine, newer-release recovery, and rescue fallback
   ✓ user configuration, credentials, identity, cache/downloads, and updater state survive

OS MAINTENANCE
   ✓ current CoreELEC pin remains recoverable
   ✓ any rebase passes baseline reconfirmation, no-Kodi/image, integration, updater, and decode gates independently of app releases
```

Unavailable required A95X `HARDWARE` or `MANUAL` proof is `BLOCKED`, never passed.

A task that cannot be verified is not a completed task.

A task whose required runner is unavailable is blocked, not completed.
