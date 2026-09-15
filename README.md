# AshipaOS

AshipaOS is a purpose-built, TV-oriented OS for single-board computers and TV
boxes: it boots straight into a 10-foot Jellyfin client experience (via a
generic Jellyfin/mpv-shim application layer) with managed OS/app updates,
rollback, provisioning, and a privileged `settingsd` service for UI-driven
system operations.

The authoritative implementation plan is [`ashipaos-build-guide.md`](ashipaos-build-guide.md).
GitHub is the source of truth; GitHub Actions is the canonical build/test
system for remotely verifiable work; physical hardware is a separate,
remotely controlled test infrastructure where available.

## Targets

| Target | Hardware | Arch | Track | Status |
|---|---|---|---|---|
| `pi4` | Raspberry Pi 4 | arm64 | Debian rootfs + image assembly | PROVISIONAL |
| `pi5` | Raspberry Pi 5 | arm64 | Debian rootfs + image assembly | PROVISIONAL |
| `x86_64` | Generic x86_64 (UEFI) | x86_64 | Debian rootfs + image assembly | PROVISIONAL |
| `a95x-f3-air` | A95X F3 Air TV box | arm64 (Amlogic) | CoreELEC-based Amlogic pipeline | PROVISIONAL |

Target definitions live under `build/targets/`; the Amlogic box
configuration lives at `build/targets/amlogic/boxes/a95x-f3-air.yaml`.
Hardware facts are labelled `CONFIRMED` / `PROVISIONAL` / `UNKNOWN` per the
build guide §1.5 — see [`contracts/hardware-facts.md`](contracts/hardware-facts.md).
A fact without evidence is not a confirmed fact.

## Verification classes

| Class | Meaning |
|---|---|
| `STATIC` | File/schema/script/config inspection, no build required |
| `BUILD` | Requires executing the build pipeline or producing an artefact |
| `VM` | Requires booting the resulting image in a virtual machine |
| `HARDWARE` | Requires the actual target hardware |
| `MANUAL` | Requires human observation or physical interaction |

A task is complete only when every required verification for that task
passes. `HARDWARE`/`MANUAL` tasks are **blocked, not passed**, when no
hardware runner is available. See [`contracts/ownership.md`](contracts/ownership.md).

## Layout

- `build/` — image build scripts, per-target config, generated dirs (`rootfs/`, `work/`, `output/` — never committed)
- `ci/` — canonical CI containers, scripts, runner definitions
- `contracts/` — ownership and interface contracts between components
- `schemas/` — JSON schemas validating target/box/manifest configs
- `rootfs-overlay/`, `packages/` — generic OS content; must contain no box-specific values (enforced by static tests)
- `provisioning/`, `settingsd/`, `updater/`, `imager/` — system components
- `tests/` — `static/`, `build/`, `vm/`, `hardware/`, `negative/` suites
- `hardware-lab/` — remote hardware test infrastructure definitions
- `evidence/` — verification evidence archive (local captures are git-ignored; committed evidence is curated)
- `amlogic-coreelec-fork/` — pinned CoreELEC checkout location (not source-controlled here)
