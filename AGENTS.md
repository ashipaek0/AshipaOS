# AshipaOS Agent Instructions

## Mandatory team workflow

Load the local Hermes skill `ashipaos-team` before any AshipaOS feature, fix, refactor, build-system change, target addition, hardware investigation, release, or maintenance task.

All work uses this gated pipeline:

`PM grooming → SWE implementation → QA verification → PM acceptance → feature-branch commit/push → PR → On-Call CI monitoring → human merge`

The Orchestrator manages lifecycle and does not implement, self-test, self-accept, or merge PRs. SWE, QA, and PM do not commit or push. The user/human reviewer merges into `main`.

## Repository identity

- Product: AshipaOS — TV-oriented Linux OS booting into a Jellyfin/mpv-shim experience.
- Repository: `ashipaek0/AshipaOS`
- Primary branch: `main`
- Authoritative plan: `ashipaos-build-guide.md`
- Canonical builder: GitHub Actions, not the developer workstation.
- Targets: `pi4`, `pi5`, `x86_64`, `a95x-f3-air`.
- Amlogic/CoreELEC is a separate build track from Debian Pi/x86_64.

Never import Epilykos paths, `dev`-branch flow, Node test commands, database/deployment rules, UI conventions, or assumptions into this repository.

## Read before changing code

1. The relevant layer/task in `ashipaos-build-guide.md`.
2. The relevant ownership/interface document in `contracts/`.
3. Target/box definitions and schemas when touching hardware or build inputs.
4. Existing tests and GitHub workflows that provide executable proof.

Do not read unrelated files merely to broaden context. Give each dispatched agent exact paths, scope, and verification requirements.

## Non-negotiable engineering contracts

- Do not invent hardware behaviour, package names, device-tree names, service names, kernel capabilities, bootloader behaviour, or target values.
- Hardware facts are `CONFIRMED`, `PROVISIONAL`, or `UNKNOWN`; a fact without evidence is not confirmed.
- Missing hardware/manual infrastructure means verification is `BLOCKED`, not passed.
- Preserve component ownership: rootfs, target definitions, image assembler, boot bundle, updater, app updater, provisioning, `settingsd`, CI, hardware lab, and release automation own distinct state.
- Keep target-specific values under `build/targets/`. Amlogic box-specific values belong under `build/targets/amlogic/boxes/`, never generic `packages/` or `rootfs-overlay/`.
- Release builds must not depend on the host kernel, undeclared host packages, mutable upstream branches, files outside declared inputs, manually copied workstation artefacts, or undeclared wall-clock values.
- Keep Wi-Fi credentials, SSH/signing private keys, Jellyfin tokens, hardware-lab credentials, and API secrets out of git.
- New Bash scripts must start with:
  ```bash
  #!/usr/bin/env bash
  set -Eeuo pipefail
  ```
  Resource-owning scripts need cleanup traps; use `mktemp` and atomic writes where practical.
- Failures must leave the build host/device recoverable. Update, provisioning, flashing, and rollback work requires negative/recovery tests.

## Verification and evidence

Every criterion names a verification class and runner:

- `STATIC` — repository/schema/script inspection.
- `BUILD` — canonical build or produced artefact.
- `VM` — boot/execution in the declared VM runner.
- `HARDWARE` — actual target through the hardware lab.
- `MANUAL` — recorded human observation.

Valid runners: `github-actions`, `hardware-lab`, `human`, `blocked`.

Every verification result records task ID, class, runner, target, result, evidence path/link, timestamp, full commit SHA, and CI run/job ID where applicable. Static success does not prove image build; VM success does not prove physical display, CEC, IR, Wi-Fi, hardware decode, or rollback.

Current static suite:

```bash
for t in tests/static/*.sh; do
  echo "=== $t ==="
  bash "$t"
done
```

This command proves only available `STATIC` checks. The current image-build job is explicitly deferred until later layer work replaces the placeholder.

## Git workflow

- Start from a clean, current `main`.
- Use isolated branches/worktrees for concurrent SWE tasks.
- Branch naming: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`, `chore/<issue>-<slug>`.
- Do not commit until QA passes available criteria and PM returns `ACCEPT`.
- Push the feature branch and open a PR to `main` with layer/task IDs, criteria, verification matrix, evidence, blocked gates, risks, rollback notes, and affected build inputs.
- Never merge the PR. Human merge only.
- On-Call monitors workflows and artefacts after push. Code regressions return to SWE → QA → PM.

## Current baseline warning

Layer 0 is scaffolded. Static tests and workflow skeletons exist, but real image builds are deferred. Target statuses are provisional. `hardware-lab/inventory.yaml` and a pinned CoreELEC checkout were absent at team creation. Re-read live state before relying on this baseline.
