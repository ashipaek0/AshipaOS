#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0
pass=0
run() {
  local name=$1; shift
  if "$@"; then
    printf 'PASS %s\n' "$name"; pass=$((pass+1))
  else
    printf 'FAIL %s\n' "$name" >&2; failures=$((failures+1))
  fi
}

run selector_partition_helper_handles_sda_and_nvme bash "$ROOT/tests/test-selector.sh" partition_helper
run selector_rejects_multiple_disks bash "$ROOT/tests/test-selector.sh" multiple
run selector_rejects_zero_disks bash "$ROOT/tests/test-selector.sh" zero
run selector_accepts_only_safe_disk bash "$ROOT/tests/test-selector.sh" safe
run selector_rejects_unsafe_devices bash "$ROOT/tests/test-selector.sh" unsafe
run selector_rejects_removable_disks bash "$ROOT/tests/test-selector.sh" removable
run selector_rejects_readonly_disks bash "$ROOT/tests/test-selector.sh" readonly
run selector_rejects_undersized_disks bash "$ROOT/tests/test-selector.sh" undersized
run selector_rejects_occupied_disks bash "$ROOT/tests/test-selector.sh" occupied
run selector_rejects_source_ancestry bash "$ROOT/tests/test-selector.sh" source
run selector_rejects_canonical_source_symlink bash "$ROOT/tests/test-selector.sh" source_symlink
run selector_handles_nvme_names bash "$ROOT/tests/test-selector.sh" nvme
run selector_rejects_bad_explicit_target bash "$ROOT/tests/test-selector.sh" explicit
run selector_rejects_device_holders bash "$ROOT/tests/test-selector.sh" holder
run selector_rejects_forced_child_without_marker bash "$ROOT/tests/test-selector.sh" child_signature
run selector_accepts_forced_valid_marker bash "$ROOT/tests/test-selector-descendants.sh" sata
run selector_rejects_forced_extra_partition bash "$ROOT/tests/test-selector.sh" force_extra_partition
run selector_rejects_env_only_force_approval bash "$ROOT/tests/test-selector.sh" force_env_only
run selector_requires_explicit_fixture_mode bash "$ROOT/tests/test-selector.sh" no_fixture_flag
run selector_rejects_wrong_marker bash "$ROOT/tests/test-selector.sh" wrong_marker
run installer_rejects_corrupt_manifest bash "$ROOT/tests/test-installer.sh" corrupt
run installer_honors_completion_guard bash "$ROOT/tests/test-installer.sh" complete
run installer_rejects_invalid_force_marker bash "$ROOT/tests/test-installer.sh" force-invalid
run installer_accepts_valid_force_marker bash "$ROOT/tests/test-installer.sh" force-valid
run installer_unmounts_then_revalidates_before_stream bash "$ROOT/tests/test-installer-revalidation.sh"
run validator_negative_cases bash "$ROOT/tests/test-negative-validators.sh"
tmpkey=$(mktemp -d)
trap 'rm -rf "$tmpkey"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$tmpkey/id_ed25519"
run ssh_accepts_valid_key "$ROOT/provision/validate-admin-key.sh" "$(cat "$tmpkey/id_ed25519.pub")"
run ssh_rejects_malformed_key bash -c "! '$ROOT/provision/validate-admin-key.sh' 'not-a-key'"
run ssh_rejects_multiline_key bash -c "! '$ROOT/provision/validate-admin-key.sh' 'ssh-ed25519 AAAA
ssh-ed25519 BBBB'"

for mode in sata nvme mmc mount mount-subpath mount-subpath-force findmnt-fail findmnt-fail-force swap holder unexpected lvm-signature raid-signature extra-signature wrong-parttype pvs mdadm dmsetup extra normal; do
  run "selector_descendants_${mode}" bash "$ROOT/tests/test-selector-descendants.sh" "$mode"
done
for mode in explicit payload-only manifest-only empty optical partitioned-usb whole-usb nonremovable-usb wrong-explicit ancestry; do
  run "source_${mode}" bash "$ROOT/tests/test-discover-source.sh" "$mode"
done
for mode in positive missing-helper missing-command missing-hyphen-module missing-xhci-module; do
  run "initramfs_closure_${mode}" bash "$ROOT/tests/test-initramfs-closure.sh" "$mode"
done
run flatpak_payload_build_runtime_commit bash "$ROOT/tests/test-flatpak-payload-build.sh"
run flatpak_export_real_collection_refs bash "$ROOT/tests/test-flatpak-export-refs.sh"
run flatpak_keyring_rejects_extra_real_primary bash "$ROOT/tests/test-flatpak-key-validation.sh"
run flatpak_offline_unprivileged_sideload bash "$ROOT/tests/test-flatpak-offline.sh"
run iso_relational_fixtures python3 -B "$ROOT/tests/test-iso-relations.py"
run vm_bios_force_mock bash "$ROOT/tests/test-vm-harness.sh" bios
run vm_uefi_force_mock bash "$ROOT/tests/test-vm-harness.sh" uefi
run vm_guard_rejects_embedded_token bash "$ROOT/tests/test-vm-harness.sh" bad-guard
run vm_force_requires_grub_to_accept_keys bash "$ROOT/tests/test-vm-harness.sh" deaf-grub

if (( failures )); then
  printf '%d passed, %d failed\n' "$pass" "$failures" >&2
  exit 1
fi
printf '%d tests passed\n' "$pass"
