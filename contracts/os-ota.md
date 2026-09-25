# A95X OS update (A/B slot) contract

Owner: image assembler (`layers/layer2-image/scripts/build-image.sh`, the
`boot.scr` it generates) for the slot-selection and rollback mechanism;
no update-delivery component exists yet (see Status below).

The image ships two ext4 root slots, `root_a` and `root_b`
(`contracts/storage.md`), and a single STORAGE partition shared by both. An OS
update replaces one *whole, unmounted* root slot's filesystem — never the
currently-running slot, never STORAGE, and never the boot partition's
per-slot files for the running slot. This is what makes an update safe to
apply while the appliance is running, and safe to interrupt or fail: the
active slot is untouched until the new one is proven to boot.

## Why whole-slot, not in-place

An in-place update (replacing files inside the running root) cannot be made
atomic against a power loss mid-write, and cannot be rolled back once
overwritten. A whole-slot update sidesteps both: the passive slot is written
in full while the active slot keeps serving the running appliance, and
switching to it is a single, atomic write of `active-root.txt` performed by
U-Boot, not Linux. This also means a single mechanism covers both an OS
update and an application update (`contracts/app-ota.md`): the application is
baked into its slot's rootfs at image-build time
(`layers/layer5-application/scripts/build-application.sh`), so shipping a new
application version is simply shipping a new slot.

## State: `active-root.txt`

A plain-text file on the FAT boot partition, the only mutable state the boot
chain depends on:

```
active_root=a
pending=0
boot_tries=0
```

It is read and rewritten only by `boot.scr`'s U-Boot logic
(`layers/layer2-image/scripts/build-image.sh`'s `boot_scr_script`), never by
Linux. On a fresh flash it always selects slot A, not pending, zero tries.

## Boot-time state machine (runs in U-Boot, before any kernel loads)

1. Load `active-root.txt`; default to `active_root=a`, `pending=0`,
   `boot_tries=0` if it is missing or unreadable.
2. If `pending=1` (a boot into a newly-updated slot that has not yet
   confirmed success): increment `boot_tries`. If `boot_tries` reaches
   `max_boot_tries` (`image-config.yaml`, currently 3), flip `active_root` to
   the other slot and reset `pending=0`, `boot_tries=0` — the revert. Write
   the (possibly reverted) state back to `active-root.txt` before proceeding.
3. Assemble `root=LABEL=RootFS-A` or `root=LABEL=RootFS-B` for whichever slot
   is now active, load that slot's `Image-<slot>` / DTB / `initrd.img-<slot>`,
   and `booti`.

Because this runs entirely in U-Boot, a slot that never reaches a Linux
console at all (bad kernel, bad DTB, corrupt filesystem) still gets counted
and eventually reverted — the appliance cannot be bricked by an update that
fails before Linux starts.

## What an update installer must do (not yet implemented — see Status)

1. Determine the passive slot (`1 - active_root` from `active-root.txt`,
   read-only at this point).
2. Write a complete new rootfs into the passive slot's partition and its
   per-slot boot files (`Image-<slot>`, `initrd.img-<slot>`,
   `<dtb>-<slot>.dtb`), verified against a signed manifest before anything is
   written, exactly as `layers/layer2-image/scripts/build-image.sh` builds a
   slot at image-build time. STORAGE and the currently-active slot must never
   be opened for writing during this step.
3. Set `active_root=<passive slot>`, `pending=1`, `boot_tries=0` in
   `active-root.txt` and reboot. From here the boot-time state machine above
   owns the outcome.
4. On the new slot's first successful boot, `ashipaos-boot-success.service`
   confirms `pending` back to `0` in `active-root.txt`
   (`rootfs-overlay/usr/libexec/ashipaos-boot-success`), once it has verified
   the appliance is actually healthy (the boot-status endpoint and the
   Jellyfin MPV Shim service both still running 20 seconds after start) —
   otherwise the very next reboot would be indistinguishable from an update
   still in progress, and the boot-tries counter would start consuming
   attempts unnecessarily. It never changes `active_root` itself, and refuses
   to write anything back if the slot it finds recorded is not `a` or `b`.

## Status

**Implemented and verified** (build- and sandbox-verified: a real
cross-compiled U-Boot executing the generated `boot.scr` against a real
partitioned image, and a real execution of `ashipaos-boot-success` against a
fake `systemctl`, not yet re-confirmed on the exact unit): the A/B partition
layout, `active-root.txt` format, the full boot-time selection/rollback state
machine in "Boot-time state machine" above, and the post-boot `pending`
confirmation step in step 4 above (`tests/e2e/test-boot-success.sh`).

**Not yet implemented**: steps 1-3 of "What an update installer must do" —
there is no code path that writes a new slot after first boot (no update
package format, no signing key, no CI export step for one, nothing that
downloads or triggers an update). Until this exists, the only way to change
what is installed is to flash a newly built image (which always writes slot A
only, per `contracts/storage.md`); the confirmation step in 4 has nothing to
confirm until then, since `pending` is never set to `1` by anything yet.
