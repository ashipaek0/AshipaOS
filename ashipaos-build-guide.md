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
- Does the A95X F3 Air boot with the selected DTB?
- Does the A95X WiFi actually work?
- Does its IR receiver work?
- Does CEC work?
- Does hardware video decoding actually use the expected decoder?
- Does 10-bit HEVC work?
- Does the physical provisioning process work?
- Does a real TV display the expected output?
- Does the remote control behave correctly?
- Does OTA rollback actually recover the physical device after a failed boot?

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

A hardware fact should be reviewed again when any of the following change:

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
 ├── docs/
 └── amlogic-coreelec-fork/
```

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

This is a separate build pipeline from the Debian Pi/x86_64 track.

The existing architecture separates:

- Amlogic-ne kernel branch scope;
- A95X F3 Air box scope;
- generic AshipaOS package/service layer.

Preserve that architecture and make the boundary enforceable.

The Amlogic track **MUST** produce:

- a working AshipaOS image for the confirmed box;
- a reusable kernel-branch-scoped AshipaOS package/service layer;
- a box configuration containing hardware-specific values;
- evidence-backed hardware facts.

---

## Task 0.5.1 — Establish Amlogic hardware facts

### Goal

Determine the exact hardware facts required to boot and operate the first supported box.

Create:

```text
build/targets/amlogic/boxes/a95x-f3-air.yaml
```

Initial schema:

```yaml
name: A95X F3 Air

status:
  device_tree: PROVISIONAL
  wifi: PROVISIONAL
  bluetooth: UNKNOWN
  ir: PROVISIONAL
  hardware_decode: PROVISIONAL

soc:
  value: S905X3
  status: PROVISIONAL

kernel_branch:
  value: Amlogic-ne
  status: PROVISIONAL

device_tree:
  value: null
  status: UNKNOWN
  evidence: []

wifi:
  driver: null
  status: UNKNOWN
  evidence: []

bluetooth:
  supported: null
  status: UNKNOWN
  evidence: []

ram:
  variants: []
  status: UNKNOWN
  evidence: []

ir:
  receiver: null
  status: UNKNOWN
  evidence: []

cec:
  status: UNKNOWN
  evidence: []

audio:
  hdmi: UNKNOWN
  analog: UNKNOWN
  spdif: UNKNOWN
  evidence: []

power:
  button: UNKNOWN
  wake_ir: UNKNOWN
  led: UNKNOWN
  evidence: []

storage:
  boot_media: UNKNOWN
  emmc_install: UNKNOWN
  evidence: []

boot:
  serial_console:
    status: UNKNOWN
    evidence: []
  recovery:
    status: UNKNOWN
    evidence: []
```

Do not put an unverified device-tree filename into the release configuration.

Use the existing procedure to inspect:

- exact device model;
- board revision;
- available CoreELEC device trees;
- serial console.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

If no hardware lab is available:

```yaml
verification:
  - class: HARDWARE
    runner: blocked
```

A specific first-choice DTB is identified.

Serial console access is available.

The result is recorded in the box configuration with `CONFIRMED` or `PROVISIONAL` status and evidence references.

---

## Task 0.5.2 — Pin CoreELEC

Clone CoreELEC and check out a specific stable release/tag.

Do not track an unpinned development branch.

Record:

```yaml
coreelec:
  repository: <repository>
  ref: <tag>
  commit: <full-commit>
```

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

Examples:

```bash
git rev-parse HEAD
git status
```

The recorded commit **MUST** equal the checked-out commit.

---

## Task 0.5.3 — Build stock CoreELEC before modifying it

### Goal

Establish a known-good hardware baseline.

Build the stock image using the CoreELEC build instructions corresponding to the pinned commit.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

On a spare SD card:

- stock image boots;
- Kodi starts;
- the selected DTB works;
- serial console can capture boot output.

Do not proceed if the baseline does not boot.

---

## Task 0.5.4 — Identify and remove Kodi

Find the Kodi package and the mechanism by which the stock image enables it.

The exploratory command remains useful:

```bash
find . -path "*/packages/mediacenter/kodi*" -name "package.mk"
```

Do not assume the package path or service name if the pinned CoreELEC version differs.

Important correction:

Do not define a “successful” image without Kodi as a finished product.

The removal-only build is an intermediate build proving the package mechanism, not a release candidate.

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

The build completes and the build log records the removed Kodi package/service.

The hardware verification confirms:

- the image boots;
- Kodi is not running;
- no broken units are caused by removal;
- the AshipaOS replacement path is identifiable.

If hardware is unavailable, the hardware verification is blocked.

---

## Task 0.5.5 — Build the generic Jellyfin/mpv-shim package

Create the AshipaOS application package using CoreELEC’s package conventions.

The package **MUST** contain no A95X-specific references.

It may contain:

- pinned Jellyfin mpv shim version;
- pinned Python dependencies;
- mpv/cage dependencies;
- generic installation logic.

It **MUST NOT** contain:

- A95X;
- F3;
- Air;
- device tree names;
- RAM variants;
- box-specific WiFi configuration.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

Example:

```bash
grep -RniE 'a95x|f3|air' packages/ashipaos/jellyfin-mpv-shim
```

Expected: no matches.

```yaml
verification:
  - class: BUILD
    runner: github-actions
```

The resulting root filesystem contains the installed package.

---

## Task 0.5.5b — Formalise box configuration

The box configuration is the only place where the physical box’s hardware-specific values are selected.

Example structure:

```yaml
name: A95X F3 Air

kernel_branch: Amlogic-ne

soc: S905X3

device_tree:
  value: <confirmed-or-provisional-dtb>
  status: PROVISIONAL
  evidence: []

wifi:
  driver_package: <driver-or-null>
  status: PROVISIONAL
  evidence: []

bluetooth:
  supported: false
  status: PROVISIONAL
  evidence: []

ram:
  variants:
    - 2G
    - 4G
  status: PROVISIONAL
  evidence: []

ir:
  receiver: <confirmed-or-null>
  status: UNKNOWN
  evidence: []
```

A box configuration may reference a driver package by name.

It **MUST NOT** embed the driver’s package implementation.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

A second box on the same kernel branch can be represented by another configuration file without modifying the generic AshipaOS package.

---

## Task 0.5.6 — Integrate AshipaOS services into CoreELEC

Identify CoreELEC’s actual overlay mechanism and service naming from the pinned source tree.

Integrate:

- display service;
- settingsd;
- provisioning;
- update services;
- input support;
- AshipaOS defaults.

The device-tree placement **MUST** consume the selected box configuration.

Do not assume a service is named `kodi.service`; verify it against the pinned CoreELEC tree.

### CoreELEC integration contract

Create:

```text
contracts/coreelec-integration.md
```

It must record, for the pinned CoreELEC ref:

```yaml
coreelec_integration:
  coreelec_ref: <tag>
  package_system: <package-system>
  service_manager: systemd
  overlay_mechanism: <mechanism>
  kodi_removal_method: <method>
  retained_services: []
  disabled_services: []
  replaced_services: []
  input_stack: <unknown-or-described>
  cec_stack: <unknown-or-described>
  ir_stack: <unknown-or-described>
  network_stack: <connman-or-other>
  update_conflicts: <none-or-described>
```

### Verification

```yaml
verification:
  - class: BUILD
    runner: github-actions

  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

The image boots directly into AshipaOS without a Kodi fallback.

---

## Task 0.5.7 — Confirm hardware decode

Test:

- H.264;
- HEVC;
- HEVC 10-bit where the hardware supports it.

The comparison against stock CoreELEC is retained.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

Record:

- media type;
- resolution;
- codec;
- decoder selected;
- CPU utilisation;
- playback result;
- relevant kernel/application errors.

Do not label hardware decode `CONFIRMED` merely because playback is smooth.

Record evidence.

---

## Task 0.5.8 — Confirm WiFi

Verify the actual driver and interface.

### Verification

```yaml
verification:
  - class: HARDWARE
    runner: hardware-lab
    target: a95x-f3-air
```

Example:

```bash
iw dev
```

Record:

- interface name;
- driver;
- firmware;
- association result;
- DHCP result.

Update the box configuration status from `PROVISIONAL` to `CONFIRMED` only after successful testing.

---

## Task 0.5.9 — Document Amlogic rebase procedure

Create:

```text
docs/amlogic-rebase-procedure.md
```

It **MUST** describe:

- selecting a new CoreELEC release;
- recording its commit;
- applying the AshipaOS patch/package set;
- validating package integration;
- validating boot;
- validating hardware decode;
- validating networking;
- validating the box configuration;
- reviewing changed hardware assumptions.

It **MUST** also contain a section:

```text
Branch scope vs box scope
```

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

A future contributor can determine whether a value is branch-scoped or box-scoped without reading the entire codebase.

---

## Task 0.5.10 — Second-box dry run

Create a hypothetical second box configuration.

Do not modify generic AshipaOS package code unless the exercise demonstrates a genuinely missing generic capability.

If a new hardware capability is required:

- add a generic schema field;
- add a standalone package if required;
- reference it from the box configuration;
- do not special-case the existing box.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
```

The second-box exercise does not require editing the generic Jellyfin package or common service overlay.

---

# LAYER 1 — Minimal Debian Root Filesystem

This layer builds the Debian Pi/x86_64 pipeline.

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

Install the Wayland compositor and required runtime libraries.

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

Play a local test file through cage before adding Jellyfin mpv shim.

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

Do not hard-code Intel VAAPI configuration into a service shared by Amlogic/Pi targets.

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

The second boot **MUST NOT** overwrite user configuration.

---

## Task 5.5 — Launch Jellyfin mpv shim

The display service launches:

```text
cage → jellyfin-mpv-shim
```

with the target’s environment and persistent application path.

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

Do not treat CEC availability as universal.

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

TV remote navigation moves focus through the UI.

---

## Task 6.4 — IR

On Amlogic hardware, first inspect the existing vendor-kernel input devices.

Do not assume that an IR receiver needs to be added from scratch.

Use `ir-keytable` only after identifying the actual receiver/input path.

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

The current `.old` model is retained for this version of the architecture.

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

# LAYER 8.5 — Jellyfin mpv-shim Application Updates

The application update mechanism remains independent of OS updates.

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

The existing `PYTHONPATH` shadowing mechanism may be retained during migration, but the final contract should use an atomic application activation point.

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

---

## Task 8.5.4 — Validate staged application

At minimum:

- package import;
- version check;
- dependency import;
- configuration load.

If validation fails, delete the pending version and leave the current version untouched.

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

---

## Task 8.5.6 — Timer

The application update timer is independent of the OS timer.

It **MUST** invoke the application update orchestrator, not merely the checker.

The service runs as root only because it needs to activate the application and restart the display service.

Its command surface must remain narrow.

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

Create:

```text
docs/amlogic-install.md
```

It **MUST** document only verified procedures.

Include:

- image writing;
- DTB placement;
- recovery boot procedure;
- expected failure behaviour;
- serial-console diagnostics.

If a step is device-firmware-specific and has not been verified, mark it `PROVISIONAL` rather than presenting it as fact.

### Verification

```yaml
verification:
  - class: STATIC
    runner: github-actions
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

Amlogic acceptance additionally requires:

```text
[ ] included IR remote tested;
[ ] 10-bit HEVC tested where applicable;
[ ] DTB and WiFi facts recorded.
```

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

Do not call this a complete A/B boot system.

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

Hardware-specific display/decode/input tests **MUST NOT** be falsely marked as passed by VM tests.

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

Amlogic boxes additionally require:

- DTB;
- serial console;
- WiFi driver;
- IR receiver;
- 10-bit HEVC where applicable.

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

- broken Python package;
- missing dependency;
- incompatible OS version;
- failed import;
- crash-looping app;
- partially written pending directory;
- corrupted state file.

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

If hardware evidence is unavailable for a required target, the release is not a release candidate for that target.

---

# 14. Quick reference build order

| Layer | Scope | Done when |
|---|---|---|
| 0 | Canonical builder environment | Toolchain, repository, and CI are controlled |
| 0.5 | Amlogic/CoreELEC | Stock baseline boots; AshipaOS replaces Kodi; box facts are separated from branch code |
| 1 | Debian rootfs | Minimal rootfs builds for explicit target |
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

---

# 15. Refactoring decisions recorded by this guide

---

## Kept

- Layer 0–10 roadmap.
- Separate Amlogic/CoreELEC pipeline.
- A95X F3 Air as first Amlogic box.
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

The manifest schema supports future signatures, but the current generation may ship with integrity-only OTA if explicitly documented.

Signing should be treated as a high-priority release-maturity item.

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

A task that cannot be verified is not a completed task.

A task whose required runner is unavailable is blocked, not completed.
